defmodule PauseAiCa.Welcome do
  @moduledoc "Small, explicitly selected welcome cohorts; drafting never sends an invitation."
  import Ecto.Query
  import Ecto.Changeset
  alias PauseAiCa.{Repo, Volunteers, Mail}
  alias PauseAiCa.Accounts.{Scope, User}
  alias PauseAiCa.Volunteers.{Group, Manager}
  alias PauseAiCa.Welcome.{Session, Participant, Event}

  def groups(scope), do: Volunteers.groups(scope)

  def hosts(scope, group_id) do
    with :ok <- manager(scope, group_id) do
      {:ok,
       Repo.all(
         from u in User,
           join: m in Manager,
           on: m.user_id == u.id,
           where: m.group_id == ^group_id and not is_nil(u.confirmed_at),
           order_by: u.email
       )}
    end
  end

  def candidates(scope, group_id) do
    with :ok <- manager(scope, group_id) do
      rows = adapter().list(scope, group_id)
      {included, excluded} = Enum.split_with(rows, &(eligible(scope, group_id, &1.id) == :ok))

      {:ok,
       %{
         included: included,
         excluded: Enum.map(excluded, &%{user: &1, reason: :withdrawn_or_suppressed})
       }}
    end
  end

  def list(scope, group_id) do
    with :ok <- manager(scope, group_id),
         do:
           {:ok,
            Repo.all(
              from s in Session,
                where: s.group_id == ^group_id,
                order_by: [desc: s.starts_at],
                preload: [:host, :participants]
            )}
  end

  def get(scope, group_id, id) do
    with :ok <- manager(scope, group_id),
         true <- uuid?(id),
         %Session{} = session <- Repo.get_by(Session, id: id, group_id: group_id) do
      {:ok, Repo.preload(session, [:host, participants: :user])}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def activity(scope, group_id, id) do
    with {:ok, _} <- get(scope, group_id, id),
         do:
           {:ok,
            Repo.all(
              from e in Event,
                where: e.group_id == ^group_id and e.session_id == ^id,
                order_by: [desc: e.inserted_at, desc: e.id]
            )}
  end

  def create(scope, group_id, attrs, command_id) do
    transact(scope, group_id, :manager, "create", command_id, attrs, fn ->
      cs =
        Session.changeset(%Session{group_id: group_id, creator_id: scope.user.id}, attrs)
        |> validate_session(scope, group_id)

      session = insert!(cs)
      {session, %{title: session.title, language: session.language}}
    end)
  end

  def update(scope, group_id, id, attrs, revision, command_id) do
    transact(scope, group_id, :manager, "update", command_id, {id, attrs, revision}, fn ->
      session = session!(group_id, id, revision)
      cs = Session.changeset(session, attrs) |> validate_session(scope, group_id)
      # Prepared drafts remain immutable snapshots; changing their schedule is
      # explicit work rather than silently rewriting a recipient's invitation.
      timing_changed =
        Enum.any?(
          ~w(starts_at ends_at timezone meeting_url language)a,
          &Map.has_key?(cs.changes, &1)
        )

      if timing_changed and
           Repo.exists?(
             from p in Participant, where: p.session_id == ^id and not is_nil(p.draft_batch_id)
           ),
         do: Repo.rollback(:prepared_drafts_exist)

      updated = update!(put_change(cs, :revision, session.revision + 1))
      {updated, %{status: updated.status, title: updated.title}}
    end)
  end

  def select(scope, group_id, id, user_ids, revision, command_id) do
    transact(scope, group_id, :manager, "select", command_id, {id, user_ids, revision}, fn ->
      session = session!(group_id, id, revision)
      if session.status != "scheduled", do: Repo.rollback(:session_closed)
      ids = if is_list(user_ids), do: Enum.uniq(user_ids), else: []
      if length(ids) not in 1..5, do: Repo.rollback(:cohort_size)

      for user_id <- ids do
        if eligible(scope, group_id, user_id) != :ok, do: Repo.rollback(:ineligible)

        if Repo.exists?(
             from p in Participant,
               join: s in Session,
               on: s.id == p.session_id,
               where:
                 p.group_id == ^group_id and p.user_id == ^user_id and p.session_id != ^id and
                   p.invitation_state in ["selected", "invited"] and s.status == "scheduled" and
                   s.ends_at > ^DateTime.utc_now()
           ),
           do: Repo.rollback(:already_scheduled)
      end

      existing =
        Repo.all(
          from p in Participant,
            where: p.session_id == ^id and p.invitation_state in ["selected", "invited"]
        )

      if length(Enum.uniq(ids ++ Enum.map(existing, & &1.user_id))) > 5,
        do: Repo.rollback(:cohort_size)

      for user_id <- ids do
        case Repo.get_by(Participant, session_id: id, user_id: user_id) do
          nil -> Repo.insert!(%Participant{group_id: group_id, session_id: id, user_id: user_id})
          %{invitation_state: state} when state in ["selected", "invited"] -> :ok
          _ -> Repo.rollback(:ineligible)
        end
      end

      updated = update!(change(session, revision: session.revision + 1))
      {updated, %{selected_user_ids: ids}}
    end)
  end

  @doc "Fresh, purpose-bound draft access; this never grants account administration or newsletter consent."
  def mail_recipient(scope, group_id, session_id, user_id) do
    with :ok <- manager(scope, group_id),
         true <- uuid?(session_id) and uuid?(user_id),
         %Session{status: "scheduled"} = session <-
           Repo.get_by(Session, id: session_id, group_id: group_id),
         true <- host_current?(group_id, session.host_id),
         true <- DateTime.compare(session.ends_at, DateTime.utc_now()) == :gt,
         %Participant{invitation_state: state, rsvp: rsvp} <-
           Repo.get_by(Participant, session_id: session_id, group_id: group_id, user_id: user_id),
         true <- state in ["selected", "invited"] and rsvp not in ["declined", "withdrawn"],
         :ok <- eligible(scope, group_id, user_id) do
      {:ok, Repo.get!(User, user_id)}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def prepare_drafts(scope, group_id, id, user_ids, revision, command_id) do
    transact(
      scope,
      group_id,
      :manager,
      "prepare_drafts",
      command_id,
      {id, user_ids, revision},
      fn ->
        session = session!(group_id, id, revision)

        if session.status != "scheduled" or not host_current?(group_id, session.host_id) or
             DateTime.compare(session.ends_at, DateTime.utc_now()) != :gt,
           do: Repo.rollback(:session_closed)

        ids = if is_list(user_ids), do: Enum.uniq(user_ids), else: []
        if length(ids) not in 1..5, do: Repo.rollback(:cohort_size)

        people =
          for user_id <- ids do
            p = Repo.get_by(Participant, session_id: id, user_id: user_id)

            if !p or p.invitation_state != "selected" or eligible(scope, group_id, user_id) != :ok,
              do: Repo.rollback(:ineligible)

            if p.draft_batch_id, do: Repo.rollback(:draft_exists)
            p
          end

        context = %{"purpose" => "welcome", "group_id" => group_id, "session_id" => id}
        batch = unwrap!(Mail.create(scope, hd(ids), context, ids))

        batch =
          unwrap!(
            Mail.save_batch(scope, batch, %{
              "recipient_ids" => ids,
              "subject" => invitation_subject(session),
              "source" => invitation_source(session)
            })
          )

        case Mail.generate(scope, batch.id) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

        for person <- people,
            do: update!(change(person, draft_batch_id: batch.id, revision: person.revision + 1))

        {batch, %{session_id: id, selected_user_ids: ids, no_send: true}}
      end
    )
  end

  def record_invited(scope, group_id, session_id, participant_id, revision, command_id) do
    transact(
      scope,
      group_id,
      :manager,
      "invitation_recorded",
      command_id,
      {session_id, participant_id, revision},
      fn ->
        session = session!(group_id, session_id)
        p = participant!(group_id, session_id, participant_id, revision)

        if session.status != "scheduled" or not host_current?(group_id, session.host_id) or
             p.invitation_state != "selected" or
             DateTime.compare(session.ends_at, DateTime.utc_now()) != :gt or
             eligible(scope, group_id, p.user_id) != :ok,
           do: Repo.rollback(:ineligible)

        updated =
          update!(
            change(p,
              invitation_state: "invited",
              invited_at: DateTime.utc_now(),
              revision: p.revision + 1
            )
          )

        {updated, %{method: "manager_recorded", provider_delivery: "unknown"}}
      end
    )
  end

  def mine(scope) do
    with :ok <- confirmed(scope) do
      {:ok,
       Repo.all(
         from p in Participant,
           where: p.user_id == ^scope.user.id and p.invitation_state != "selected",
           order_by: [desc: p.updated_at],
           preload: [:group, session: :host]
       )
       |> Enum.map(fn p ->
         active = active_participation?(p, p.session)

         session = %{
           p.session
           | meeting_url: if(active and p.rsvp == "accepted", do: p.session.meeting_url)
         }

         %{p | active: active, session: session}
       end)}
    end
  end

  def respond(scope, id, reply, revision, command_id)
      when reply in ~w(accepted declined withdrawn) do
    with :ok <- confirmed(scope),
         true <- uuid?(id),
         %Participant{} = existing <- Repo.get_by(Participant, id: id, user_id: scope.user.id) do
      transact(
        scope,
        existing.group_id,
        :participant,
        "rsvp",
        command_id,
        {id, reply, revision},
        fn ->
          p = participant!(existing.group_id, existing.session_id, id, revision)
          s = session!(p.group_id, p.session_id)

          if p.user_id != scope.user.id or p.invitation_state != "invited" or
               s.status != "scheduled" or
               (reply == "accepted" and not active_participation?(p, s)),
             do: Repo.rollback(:ineligible)

          updated =
            update!(
              change(p,
                rsvp: reply,
                responded_at: DateTime.utc_now(),
                invitation_state: if(reply == "withdrawn", do: "withdrawn", else: "invited"),
                revision: p.revision + 1
              )
            )

          {updated, %{rsvp: reply}}
        end
      )
    else
      _ -> {:error, :unauthorized}
    end
  end

  def respond(_, _, _, _, _), do: {:error, :invalid}

  def record_outcome(scope, group_id, session_id, participant_id, attrs, revision, command_id) do
    transact(
      scope,
      group_id,
      :manager,
      "outcome_recorded",
      command_id,
      {session_id, participant_id, attrs, revision},
      fn ->
        session = session!(group_id, session_id)
        p = participant!(group_id, session_id, participant_id, revision)
        attendance = Map.get(attrs, "attendance", p.attendance)
        follow_up = Map.get(attrs, "follow_up", p.follow_up)

        if attendance not in ~w(unknown attended no_show) or
             follow_up not in ~w(pending completed),
           do: Repo.rollback(:invalid)

        if attendance != "unknown" and
             DateTime.compare(session.starts_at, DateTime.utc_now()) == :gt,
           do: Repo.rollback(:not_started)

        if attendance == "no_show" and
             DateTime.compare(session.ends_at, DateTime.utc_now()) == :gt,
           do: Repo.rollback(:not_finished)

        cs =
          p
          |> cast(attrs, [:notes])
          |> validate_length(:notes, max: 2000)
          |> put_change(:attendance, attendance)
          |> put_change(:follow_up, follow_up)
          |> put_change(:attendance_by_id, scope.user.id)
          |> put_change(:revision, p.revision + 1)

        updated = update!(cs)

        {updated,
         %{
           attendance: attendance,
           follow_up: follow_up,
           notes_changed: Map.has_key?(cs.changes, :notes)
         }}
      end
    )
  end

  def move(scope, group_id, participant_id, target_id, revision, command_id) do
    transact(
      scope,
      group_id,
      :manager,
      "moved",
      command_id,
      {participant_id, target_id, revision},
      fn ->
        if !uuid?(participant_id) or !uuid?(target_id), do: Repo.rollback(:not_found)

        p =
          Repo.get_by(Participant, id: participant_id, group_id: group_id) ||
            Repo.rollback(:not_found)

        if p.revision != revision, do: Repo.rollback(:conflict)
        target = session!(group_id, target_id)

        if p.invitation_state not in ["selected", "invited"] or target.status != "scheduled" or
             DateTime.compare(target.ends_at, DateTime.utc_now()) != :gt or
             target.id == p.session_id or eligible(scope, group_id, p.user_id) != :ok or
             Repo.get_by(Participant, session_id: target.id, user_id: p.user_id),
           do: Repo.rollback(:ineligible)

        count =
          Repo.aggregate(
            from(x in Participant,
              where: x.session_id == ^target.id and x.invitation_state in ["selected", "invited"]
            ),
            :count
          )

        if count >= 5, do: Repo.rollback(:cohort_size)
        update!(change(p, invitation_state: "moved", revision: p.revision + 1))

        moved =
          Repo.insert!(%Participant{
            group_id: group_id,
            session_id: target.id,
            user_id: p.user_id
          })

        {moved, %{from_session_id: p.session_id, prior_participant_id: p.id, no_send: true}}
      end
    )
  end

  @doc "Uses PostgreSQL's maintained IANA rules; gap and repeated local times are rejected."
  def local_time(value, zone) when is_binary(value) and is_binary(zone) do
    with {:ok, naive} <-
           NaiveDateTime.from_iso8601(if byte_size(value) == 16, do: value <> ":00", else: value),
         %{rows: [[true]]} <-
           Repo.query!("SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=$1)", [zone]) do
      %{rows: [[utc, roundtrip, before, after_time]]} =
        Repo.query!(
          "SELECT (($1::timestamp AT TIME ZONE $2) AT TIME ZONE 'UTC'), (($1::timestamp AT TIME ZONE $2) AT TIME ZONE $2), ((($1::timestamp AT TIME ZONE $2)-interval '1 hour') AT TIME ZONE $2), ((($1::timestamp AT TIME ZONE $2)+interval '1 hour') AT TIME ZONE $2)",
          [naive, zone]
        )

      if NaiveDateTime.compare(roundtrip, naive) == :eq and
           NaiveDateTime.compare(before, naive) != :eq and
           NaiveDateTime.compare(after_time, naive) != :eq,
         do: {:ok, DateTime.from_naive!(utc, "Etc/UTC")},
         else: {:error, :clock_change}
    else
      _ -> {:error, :invalid_time}
    end
  end

  def local_time(_, _), do: {:error, :invalid_time}

  def display_time(%DateTime{} = datetime, zone) do
    %{rows: [[local]]} = Repo.query!("SELECT $1::timestamptz AT TIME ZONE $2", [datetime, zone])
    Calendar.strftime(local, "%Y-%m-%d %H:%M") <> " · " <> zone
  end

  defp validate_session(cs, _scope, group_id) do
    host = get_field(cs, :host_id)

    cs =
      if host_current?(group_id, host),
        do: cs,
        else: add_error(cs, :host_id, "must be a current confirmed group manager")

    start = get_field(cs, :starts_at)
    finish = get_field(cs, :ends_at)

    cs =
      if start && finish && DateTime.compare(finish, start) != :gt,
        do: add_error(cs, :ends_at, "must follow the start"),
        else: cs

    cs =
      if finish && get_field(cs, :status) == "completed" &&
           DateTime.compare(finish, DateTime.utc_now()) == :gt,
         do: add_error(cs, :status, "cannot complete a future call"),
         else: cs

    zone = get_field(cs, :timezone)

    if is_binary(zone) &&
         Repo.query!("SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=$1)", [zone]).rows ==
           [[true]], do: cs, else: add_error(cs, :timezone, "must be an IANA timezone")
  end

  defp host_current?(group_id, host) do
    uuid?(host) and
      Repo.exists?(
        from m in Manager,
          join: u in User,
          on: u.id == m.user_id,
          where: m.group_id == ^group_id and m.user_id == ^host and not is_nil(u.confirmed_at)
      )
  end

  defp eligible(scope, group_id, user_id) do
    with true <- uuid?(user_id),
         {:ok, %User{id: ^user_id}} <- adapter().fetch(scope, group_id, user_id),
         %User{confirmed_at: at, email: email} when not is_nil(at) <- Repo.get(User, user_id),
         false <- Mail.suppressed?(email),
         false <- withdrawn_from_group?(user_id, group_id) do
      :ok
    else
      _ -> {:error, :ineligible}
    end
  end

  defp withdrawn_from_group?(user_id, group_id),
    do:
      Repo.exists?(
        from p in Participant,
          where: p.group_id == ^group_id and p.user_id == ^user_id and p.rsvp == "withdrawn"
      )

  defp active_participation?(participant, session) do
    participant.invitation_state == "invited" and session.status == "scheduled" and
      DateTime.compare(session.ends_at, DateTime.utc_now()) == :gt and
      host_current?(participant.group_id, session.host_id) and
      not withdrawn_from_group?(participant.user_id, participant.group_id) and
      Code.ensure_loaded?(adapter()) and function_exported?(adapter(), :related?, 2) and
      adapter().related?(participant.user_id, participant.group_id)
  end

  defp adapter,
    do:
      Application.get_env(
        :pauseai_ca,
        :welcome_participant_adapter,
        PauseAiCa.Welcome.AccountParticipants
      )

  defp manager(scope, group_id),
    do:
      if(uuid?(group_id) and Enum.any?(groups(scope), &(&1.id == group_id)),
        do: :ok,
        else: {:error, :unauthorized}
      )

  defp confirmed(%Scope{user: %{id: id}}),
    do:
      if(Repo.exists?(from u in User, where: u.id == ^id and not is_nil(u.confirmed_at)),
        do: :ok,
        else: {:error, :unauthorized}
      )

  defp confirmed(_), do: {:error, :unauthorized}
  defp uuid?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))

  defp session!(group_id, id, revision \\ nil) do
    if !uuid?(id), do: Repo.rollback(:not_found)
    session = Repo.get_by(Session, id: id, group_id: group_id) || Repo.rollback(:not_found)
    if revision && session.revision != revision, do: Repo.rollback(:conflict)
    session
  end

  defp participant!(group_id, session_id, id, revision) do
    if !uuid?(id), do: Repo.rollback(:not_found)

    p =
      Repo.get_by(Participant, id: id, group_id: group_id, session_id: session_id) ||
        Repo.rollback(:not_found)

    if p.revision != revision, do: Repo.rollback(:conflict)
    p
  end

  defp transact(scope, group_id, authority, action, key, input, callback) do
    permission = if authority == :manager, do: manager(scope, group_id), else: confirmed(scope)

    with :ok <- permission, true <- is_binary(key) and byte_size(key) in 1..200 do
      Repo.transaction(fn ->
        Repo.one!(from g in Group, where: g.id == ^group_id, lock: "FOR UPDATE")

        if if(authority == :manager, do: manager(scope, group_id), else: confirmed(scope)) != :ok,
          do: Repo.rollback(:unauthorized)

        fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({action, input}))

        case Repo.get_by(Event, group_id: group_id, actor_id: scope.user.id, command_id: key) do
          %Event{fingerprint: ^fingerprint} = event ->
            replay(scope, event)

          %Event{} ->
            Repo.rollback(:command_conflict)

          nil ->
            {result, details} = callback.()

            {kind, session_id, participant_id} =
              case result do
                %Session{} -> {"session", result.id, nil}
                %Participant{} -> {"participant", result.session_id, result.id}
                %Mail.Batch{} -> {"draft", Map.fetch!(details, :session_id), nil}
              end

            Repo.insert!(%Event{
              group_id: group_id,
              session_id: session_id,
              participant_id: participant_id,
              actor_id: scope.user.id,
              action: action,
              command_id: key,
              fingerprint: fingerprint,
              result_kind: kind,
              result_id: result.id,
              details: details
            })

            result
        end
      end)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid}
    end
  end

  defp replay(scope, %{result_kind: "draft", result_id: id}) do
    case Mail.get(scope, id) do
      {:ok, batch} -> batch
      _ -> Repo.rollback(:unauthorized)
    end
  end

  defp replay(_, %{result_kind: "session", result_id: id}), do: Repo.get!(Session, id)
  defp replay(_, %{result_kind: "participant", result_id: id}), do: Repo.get!(Participant, id)
  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, reason}), do: Repo.rollback(reason)

  defp insert!(cs) do
    case Repo.insert(cs) do
      {:ok, result} -> result
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp update!(cs) do
    case Repo.update(cs) do
      {:ok, result} -> result
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp invitation_subject(%{language: "fr", title: title}), do: "Appel d’accueil : " <> title
  defp invitation_subject(%{title: title}), do: "Welcome call: " <> title

  defp invitation_source(session) do
    path = if session.language == "fr", do: "/fr/appels-accueil", else: "/en/welcome-calls"
    url = PauseAiCaWeb.Site.url(session.language, path)

    if session.language == "fr" do
      "Bonjour,\n\nNous vous invitons à notre appel d’accueil : **#{session.title}**.\n\n#{display_time(session.starts_at, session.timezone)} → #{display_time(session.ends_at, session.timezone)}\n\n[Répondre à l’invitation](#{url})\n\nVotre réponse ne vous inscrit pas à une infolettre et n’accorde aucune adhésion à un groupe."
    else
      "Hello,\n\nYou're invited to our welcome call: **#{session.title}**.\n\n#{display_time(session.starts_at, session.timezone)} → #{display_time(session.ends_at, session.timezone)}\n\n[Respond to the invitation](#{url})\n\nYour reply does not subscribe you to a newsletter or grant group membership."
    end
  end
end
