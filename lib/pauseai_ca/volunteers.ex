defmodule PauseAiCa.Volunteers do
  @moduledoc "Local volunteer signup drafts, group permissions and invitation history."
  import Ecto.Query
  import Ecto.Changeset
  require Logger

  alias PauseAiCa.{Accounts, Repo}
  alias PauseAiCa.Accounts.{Scope, User, UserToken}
  alias PauseAiCa.ContactMigration.Contact
  alias PauseAiCa.Volunteers.{Batch, Event, Group, Input, Invitation, Manager, Profile, Signup}

  def allowed?(scope), do: superadmin?(scope) or groups(scope) != []

  def superadmin?(%Scope{user: %{id: id}}),
    do:
      Repo.exists?(
        from u in User, where: u.id == ^id and u.superadmin == true and not is_nil(u.confirmed_at)
      )

  def superadmin?(_), do: false

  def groups(%Scope{user: %{id: id}} = scope) do
    if superadmin?(scope) do
      Repo.all(from g in Group, order_by: g.name)
    else
      Repo.all(
        from g in Group,
          join: m in Manager,
          on: m.group_id == g.id,
          join: u in User,
          on: u.id == m.user_id,
          where: m.user_id == ^id and not is_nil(u.confirmed_at),
          order_by: g.name
      )
    end
  end

  def groups(_), do: []

  def create_group(scope, attrs) do
    if superadmin?(scope) do
      %Group{}
      |> cast(attrs, [:name])
      |> update_change(:name, &String.trim/1)
      |> validate_required([:name])
      |> validate_length(:name, max: 100)
      |> unique_constraint(:name, name: :volunteer_groups_lower_index)
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  def managers(scope) do
    if superadmin?(scope),
      do: Repo.all(from m in Manager, preload: [:group, :user], order_by: m.inserted_at),
      else: []
  end

  def assign_manager(scope, group_id, email) do
    with true <- superadmin?(scope),
         {:ok, _} <- Ecto.UUID.cast(group_id),
         %Group{} <- Repo.get(Group, group_id),
         %User{confirmed_at: confirmed, id: user_id} when not is_nil(confirmed) <-
           Accounts.get_user_by_email(String.downcase(String.trim(email))) do
      %Manager{}
      |> change(group_id: group_id, user_id: user_id)
      |> unique_constraint([:group_id, :user_id])
      |> Repo.insert(on_conflict: :nothing)
    else
      _ -> {:error, :unauthorized}
    end
  end

  def revoke_manager(scope, manager_id) do
    if superadmin?(scope) and valid_id?(manager_id) do
      Repo.delete_all(from m in Manager, where: m.id == ^manager_id)
      :ok
    else
      {:error, :unauthorized}
    end
  end

  def list_batches(scope) do
    if allowed?(scope) do
      admin? = superadmin?(scope)

      Repo.all(
        from b in Batch,
          where: b.owner_id == ^scope.user.id or ^admin?,
          order_by: [desc: b.updated_at],
          limit: 50
      )
      |> Enum.filter(&authorized_batch?(scope, &1))
    else
      []
    end
  end

  def get_batch(scope, id) do
    with true <- allowed?(scope) and valid_id?(id),
         %Batch{} = batch <- Repo.get(Batch, id),
         true <-
           (batch.owner_id == scope.user.id or superadmin?(scope)) and
             authorized_batch?(scope, batch) do
      {:ok, batch}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def save_draft(scope, batch, attrs) do
    if allowed?(scope) do
      rows = Enum.map(Map.get(attrs, "rows", []), &Input.normalize/1)
      batch = batch || %Batch{owner_id: scope.user.id}
      default = blank_nil(attrs["default_group_id"])

      changes = %{
        entry_mode: attrs["entry_mode"] || batch.entry_mode,
        rows: rows,
        csv_mapping: attrs["csv_mapping"] || batch.csv_mapping,
        default_group_id: default,
        source: attrs["source"] || "",
        step: attrs["step"] || "rows",
        wizard_row: attrs["wizard_row"]
      }

      candidate = struct(batch, changes)

      cond do
        batch.owner_id != scope.user.id or batch.state != "draft" ->
          {:error, :unauthorized}

        length(rows) > 1000 ->
          {:error, :too_many_rows}

        not authorized_batch?(scope, candidate) ->
          {:error, :unauthorized}

        true ->
          result =
            batch
            |> change(changes)
            |> validate_inclusion(:entry_mode, ~w(single multiple))
            |> validate_length(:source, max: 200)
            |> validate_inclusion(:step, ~w(rows contact contribution review))
            |> optimistic_lock(:version)
            |> Repo.insert_or_update(stale_error_field: :version)

          result
      end
    else
      {:error, :unauthorized}
    end
  rescue
    _ in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :unavailable}
  end

  def discard_draft(scope, id) do
    with {:ok, batch} <- get_batch(scope, id), true <- batch.state == "draft" do
      Repo.delete_all(from b in Batch, where: b.id == ^batch.id and b.state == "draft")
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  def review(scope, rows, default_group_id) do
    available = groups(scope)
    admin? = superadmin?(scope)

    frequencies =
      rows |> Enum.map(&String.downcase(String.trim(&1["email"] || ""))) |> Enum.frequencies()

    emails = Map.keys(frequencies)
    signups = Repo.all(from s in Signup, where: s.email in ^emails) |> Map.new(&{&1.email, &1})

    users =
      Repo.all(from u in User, where: fragment("lower(?)", u.email) in ^emails)
      |> Map.new(&{String.downcase(&1.email), &1})

    suppressed =
      Repo.all(
        from c in Contact,
          where: c.email in ^emails and c.classification == "do_not_contact",
          select: c.email
      )
      |> MapSet.new()

    Enum.map(rows, fn input ->
      row = Input.normalize(input)
      group = resolve_group(available, blank_nil(row["group_id"]) || default_group_id)
      errors = Input.errors(row)

      errors =
        if group == :invalid or (group == nil and not admin?),
          do: Map.put(errors, "group_id", :unauthorized_group),
          else: errors

      errors =
        if frequencies[row["email"]] > 1, do: Map.put(errors, "email", :duplicate), else: errors

      signup = signups[row["email"]]
      user = users[row["email"]]
      suppressed? = MapSet.member?(suppressed, row["email"])

      status =
        cond do
          suppressed? ->
            :suppressed

          signup != nil and (admin? or Enum.any?(available, &(&1.id == signup.group_id))) ->
            :already_imported

          signup != nil or (user != nil and not admin?) ->
            :needs_admin

          user != nil ->
            :existing_account

          true ->
            :new_account
        end

      errors =
        if status in [:suppressed, :already_imported, :needs_admin],
          do: Map.put(errors, "email", status),
          else: errors

      %{row: row, group: group, errors: errors, status: status}
    end)
  end

  def confirm(scope, id) do
    Repo.transaction(fn ->
      with {:ok, batch} <- get_batch(scope, id) do
        batch = Repo.one!(from b in Batch, where: b.id == ^batch.id, lock: "FOR UPDATE")

        if batch.state == "confirmed" do
          batch
        else
          selected = Enum.filter(batch.rows, &(&1["selected"] == true))
          reviewed = review(scope, selected, batch.default_group_id)

          if selected == [] or Enum.any?(reviewed, &(&1.errors != %{})),
            do: Repo.rollback(:invalid_rows)

          reviewed
          |> Enum.sort_by(& &1.row["email"])
          |> Enum.each(fn entry ->
            # Serialize imports of the same normalized address across concurrent batches.
            Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
              entry.row["email"]
            ])

            fresh = hd(review(scope, [entry.row], batch.default_group_id))
            if fresh.errors != %{}, do: Repo.rollback(:rows_changed)
            create_signup(scope, batch, fresh)
          end)

          batch = batch |> change(state: "confirmed", step: "review") |> Repo.update!()

          event(scope.user.id, batch.id, nil, "batch_confirmed", %{
            "selected_count" => length(selected)
          })

          batch
        end
      else
        _ -> Repo.rollback(:unauthorized)
      end
    end)
  end

  def results(scope, batch_id) do
    with {:ok, batch} <- get_batch(scope, batch_id) do
      Repo.all(
        from s in Signup,
          where: s.batch_id == ^batch.id,
          preload: [:user, :group, invitations: ^from(i in Invitation, order_by: i.inserted_at)],
          order_by: s.email
      )
    else
      _ -> []
    end
  end

  def events(scope, batch_id) do
    with {:ok, batch} <- get_batch(scope, batch_id) do
      Repo.all(
        from e in Event,
          where: e.batch_id == ^batch.id,
          order_by: [desc: e.inserted_at],
          preload: [:actor]
      )
    else
      _ -> []
    end
  end

  def retry(scope, invitation_id) do
    Repo.transaction(fn ->
      invitation = invitation_for!(scope, invitation_id)
      if invitation.status != "failed", do: Repo.rollback(:not_retryable)
      invitation |> change(status: "retried") |> Repo.update!()
      next = Repo.insert!(%Invitation{signup_id: invitation.signup_id, actor_id: scope.user.id})

      event(
        scope.user.id,
        invitation.signup.batch_id,
        invitation.signup_id,
        "invitation_retry_requested",
        %{"invitation_id" => next.id}
      )

      next
    end)
  end

  def resend(scope, invitation_id) do
    Repo.transaction(fn ->
      invitation = invitation_for!(scope, invitation_id)
      if invitation.status != "accepted", do: Repo.rollback(:not_retryable)
      # The original attempt is consumed once; concurrent/repeated clicks cannot resend it twice.
      invitation |> change(status: "resent") |> Repo.update!()
      next = Repo.insert!(%Invitation{signup_id: invitation.signup_id, actor_id: scope.user.id})

      event(
        scope.user.id,
        invitation.signup.batch_id,
        invitation.signup_id,
        "invitation_resend_requested",
        %{"invitation_id" => next.id}
      )

      next
    end)
  end

  def reconcile(scope, invitation_id, outcome, reference) do
    Repo.transaction(fn ->
      invitation = invitation_for!(scope, invitation_id)

      if not superadmin?(scope) or invitation.status != "unknown" or
           outcome not in ["accepted", "failed"] or String.trim(reference) == "",
         do: Repo.rollback(:not_retryable)

      changed =
        invitation
        |> change(
          status: outcome,
          provider_id: String.slice(reference, 0, 200),
          completed_at: DateTime.utc_now(:second)
        )
        |> Repo.update!()

      event(
        scope.user.id,
        invitation.signup.batch_id,
        invitation.signup_id,
        "invitation_reconciled",
        %{"outcome" => outcome, "reference" => String.slice(reference, 0, 200)}
      )

      changed
    end)
  end

  def dispatch_batch(scope, batch_id, deliver \\ &deliver_invitation/1) do
    with {:ok, _batch} <- get_batch(scope, batch_id) do
      from(i in Invitation,
        join: s in Signup,
        on: s.id == i.signup_id,
        where: s.batch_id == ^batch_id and i.status == "queued",
        select: i.id
      )
      |> Repo.all()
      |> Enum.each(&dispatch(&1, deliver))

      :ok
    end
  end

  def dispatch_pending do
    # A interrupted send has an unknown provider outcome; never silently retry it.
    Repo.transaction(fn ->
      stale =
        Repo.all(
          from i in Invitation,
            where: i.status == "sending" and i.attempted_at < ago(15, "minute"),
            lock: "FOR UPDATE SKIP LOCKED",
            preload: [:signup]
        )

      for invitation <- stale do
        invitation
        |> change(status: "unknown", completed_at: DateTime.utc_now(:second))
        |> Repo.update!()

        event(
          invitation.actor_id,
          invitation.signup.batch_id,
          invitation.signup_id,
          "invitation_unknown",
          %{"invitation_id" => invitation.id, "reason" => "interrupted_dispatch"}
        )
      end
    end)

    Repo.all(from i in Invitation, where: i.status == "queued", limit: 100, select: i.id)
    |> Enum.each(fn id -> dispatch(id, &deliver_invitation/1) end)
  end

  def get_profile(scope) do
    Repo.get_by(Profile, user_id: scope.user.id) || %Profile{user_id: scope.user.id}
  end

  def save_profile(scope, attrs, step, publish? \\ false) do
    values = Input.profile(attrs)
    errors = Input.profile_errors(values)

    if errors == %{} and step in ~w(contact contribution review) do
      profile = get_profile(scope)
      changes = %{draft: values, step: step}

      changes =
        if publish?, do: Map.put(changes, :details, Input.profile_details(values)), else: changes

      profile |> change(changes) |> unique_constraint(:user_id) |> Repo.insert_or_update()
    else
      {:error, errors}
    end
  rescue
    _ in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :unavailable}
  end

  defp create_signup(scope, batch, %{row: row, group: group}) do
    user =
      Repo.one(from u in User, where: fragment("lower(?)", u.email) == ^row["email"], limit: 1)

    user =
      user ||
        %User{}
        |> User.registration_changeset(row)
        |> change(name: blank_nil(row["name"]), signup_entry_point: "volunteer_signup")
        |> Repo.insert!()

    user =
      user
      |> change(organizing_group_id: group && group.id, organizer_notes: row["notes"])
      |> Repo.update!()

    signup =
      Repo.insert!(%Signup{
        email: row["email"],
        user_id: user.id,
        batch_id: batch.id,
        group_id: group && group.id,
        notes: row["notes"]
      })

    profile = Input.profile(row)

    Repo.insert(
      %Profile{user_id: user.id, details: Input.profile_details(profile), draft: profile},
      on_conflict: :nothing,
      conflict_target: [:user_id]
    )

    invitation = Repo.insert!(%Invitation{signup_id: signup.id, actor_id: scope.user.id})

    event(scope.user.id, batch.id, signup.id, "account_linked", %{
      "invitation_id" => invitation.id,
      "user_id" => user.id
    })

    signup
  end

  defp dispatch(id, deliver) do
    now = DateTime.utc_now(:second)

    {claimed, _} =
      Repo.update_all(from(i in Invitation, where: i.id == ^id and i.status == "queued"),
        set: [status: "sending", attempted_at: now, updated_at: now]
      )

    if claimed == 1 do
      invitation = Repo.get!(Invitation, id) |> Repo.preload(signup: [:user])
      signup = invitation.signup

      outcome =
        if Repo.exists?(
             from c in Contact,
               where: c.email == ^signup.email and c.classification == "do_not_contact"
           ) do
          {:error, :suppressed}
        else
          try do
            deliver.(signup.user)
          rescue
            _ -> {:error, :unknown}
          catch
            _, _ -> {:error, :unknown}
          end
        end

      {status, provider_id} =
        case outcome do
          {:ok, metadata} when is_map(metadata) ->
            {"accepted", safe_provider_id(metadata)}

          {:error, reason} when reason in [:timeout, :unknown] ->
            {"unknown", nil}

          {:error, :suppressed} ->
            {"suppressed", nil}

          {:error, :rejected} ->
            {"failed", nil}

          {:error, {code, _}}
          when is_integer(code) and code >= 400 and code < 500 and code != 408 ->
            {"failed", nil}

          {:error, _} ->
            {"unknown", nil}

          _ ->
            {"unknown", nil}
        end

      invitation
      |> change(status: status, provider_id: provider_id, completed_at: DateTime.utc_now(:second))
      |> Repo.update!()

      event(invitation.actor_id, signup.batch_id, signup.id, "invitation_" <> status, %{
        "invitation_id" => id,
        "provider_id" => provider_id
      })

      Logger.info(
        "volunteer_invitation outcome=#{status} invitation_id=#{id} batch_id=#{signup.batch_id}"
      )
    end
  end

  def deliver_invitation(user) do
    {encoded, token} = UserToken.build_email_token(user, "login")
    Repo.insert!(token)

    PauseAiCa.Accounts.UserNotifier.deliver_volunteer_invitation(
      user,
      PauseAiCaWeb.Endpoint.url() <> "/users/log-in/" <> encoded
    )
  end

  defp safe_provider_id(metadata) do
    value = metadata[:id] || metadata["id"] || metadata[:message_id] || metadata["messageId"]
    if is_binary(value), do: String.slice(value, 0, 200), else: nil
  end

  defp invitation_for!(scope, id) do
    with true <- valid_id?(id),
         %Invitation{} = invitation <-
           Repo.one(from i in Invitation, where: i.id == ^id, lock: "FOR UPDATE"),
         invitation <- Repo.preload(invitation, :signup),
         true <- authorized_group?(scope, invitation.signup.group_id) do
      invitation
    else
      _ -> Repo.rollback(:unauthorized)
    end
  end

  defp authorized_batch?(scope, %{state: "confirmed", id: id}) do
    superadmin?(scope) or
      Enum.all?(
        Repo.all(from s in Signup, where: s.batch_id == ^id, select: s.group_id),
        &authorized_group?(scope, &1)
      )
  end

  defp authorized_batch?(scope, batch) do
    available = groups(scope)
    admin? = superadmin?(scope)

    Enum.all?(
      [
        batch.default_group_id
        | Enum.map(batch.rows, &(blank_nil(&1["group_id"]) || batch.default_group_id))
      ],
      fn id ->
        group = resolve_group(available, id)
        group != :invalid and (group != nil or admin?)
      end
    )
  end

  defp authorized_group?(scope, id),
    do: superadmin?(scope) or Enum.any?(groups(scope), &(&1.id == id))

  defp resolve_group(_groups, id) when id in [nil, ""], do: nil

  defp resolve_group(groups, value),
    do:
      Enum.find(
        groups,
        :invalid,
        &(&1.id == value or String.downcase(&1.name) == String.downcase(value))
      )

  defp blank_nil(value) when value in [nil, ""], do: nil
  defp blank_nil(value), do: value
  defp valid_id?(value), do: match?({:ok, _}, Ecto.UUID.cast(value))

  defp event(actor_id, batch_id, signup_id, action, details),
    do:
      Repo.insert!(%Event{
        actor_id: actor_id,
        batch_id: batch_id,
        signup_id: signup_id,
        action: action,
        details: details
      })
end
