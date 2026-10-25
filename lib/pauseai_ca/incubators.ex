defmodule PauseAiCa.Incubators do
  @moduledoc "Configured public groups and account-linked admission with fresh scoped authority."
  import Ecto.Query
  import Ecto.Changeset
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.{Scope, User}
  alias PauseAiCa.Volunteers.{Group, Manager}
  alias PauseAiCa.Incubators.{Profile, Membership, Event}

  @public ~w(group_id name_en name_fr summary_en summary_fr fsas events_url moderator_contact whatsapp_enabled)a
  @profile_fields Enum.reject(@public, &(&1 == :group_id)) ++
                    [:published, :whatsapp_invite_url, :whatsapp_approval_confirmed]

  def public_groups(fsa \\ nil) do
    Repo.all(from p in Profile, where: p.published, order_by: p.name_en)
    |> Enum.map(&Map.take(&1, @public))
    |> Enum.sort_by(fn p -> {fsa not in p.fsas, p.name_en} end)
  end

  def public_group(id) do
    if uuid?(id) do
      case Repo.get_by(Profile, group_id: id, published: true) do
        nil -> {:error, :not_found}
        p -> {:ok, Map.take(p, @public)}
      end
    else
      {:error, :not_found}
    end
  end

  def managed_groups(scope), do: Volunteers.groups(scope)

  def configure(scope, group_id, attrs, revision \\ nil) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    with :ok <- manager(scope, group_id) do
      transaction(fn ->
        lock_group!(scope, group_id)
        current = Repo.get_by(Profile, group_id: group_id) || %Profile{group_id: group_id}
        if current.id && current.revision != revision, do: Repo.rollback(:stale)

        if Map.has_key?(attrs, "published") && truthy?(attrs["published"]) != current.published &&
             not Volunteers.superadmin?(scope),
           do: Repo.rollback(:forbidden)

        attrs =
          if Map.has_key?(attrs, "fsas"),
            do: Map.update!(attrs, "fsas", &parse_fsas/1),
            else: attrs

        changeset =
          current
          |> cast(attrs, @profile_fields)
          |> validate_required([:name_en, :name_fr])
          |> validate_length(:name_en, max: 100)
          |> validate_length(:name_fr, max: 100)
          |> validate_length(:summary_en, max: 2000)
          |> validate_length(:summary_fr, max: 2000)
          |> validate_length(:moderator_contact, max: 200)
          |> validate_change(:fsas, fn :fsas, xs ->
            if Enum.all?(
                 xs,
                 &Regex.match?(~r/^[ABCEGHJKLMNPRSTVXY][0-9][ABCEGHJKLMNPRSTVWXYZ]$/, &1)
               ),
               do: [],
               else: [fsas: "use the first three postal-code characters, for example H2X"]
          end)
          |> validate_url(:events_url)
          |> validate_url(:whatsapp_invite_url)

        changeset =
          if get_field(changeset, :whatsapp_enabled) &&
               (!get_field(changeset, :whatsapp_approval_confirmed) ||
                  blank?(get_field(changeset, :moderator_contact))),
             do:
               add_error(
                 changeset,
                 :whatsapp_approval_confirmed,
                 "confirm manager-controlled admission and provide a moderator contact"
               ),
             else: changeset

        changeset = if current.id, do: optimistic_lock(changeset, :revision), else: changeset

        case Repo.insert_or_update(changeset) do
          {:ok, p} ->
            event(scope, group_id, nil, "configure", %{revision: p.revision})
            {:ok, p}

          {:error, cs} ->
            {:error, cs}
        end
      end)
    end
  end

  def configuration(scope, group_id) do
    with :ok <- manager(scope, group_id), do: {:ok, Repo.get_by(Profile, group_id: group_id)}
  end

  def mine(scope, group_id) do
    with :ok <- confirmed(scope), true <- uuid?(group_id) do
      membership = Repo.get_by(Membership, group_id: group_id, user_id: scope.user.id)
      {:ok, if(membership, do: applicant_view(membership), else: nil)}
    else
      _ -> {:error, :forbidden}
    end
  end

  def request(scope, group_id, attrs, revision \\ nil) do
    with :ok <- confirmed(scope), {:ok, profile} <- public_group(group_id) do
      transaction(fn ->
        if is_nil(Repo.one(from g in Group, where: g.id == ^group_id, lock: "FOR UPDATE")),
          do: Repo.rollback(:forbidden)

        if confirmed(scope) != :ok ||
             !Repo.exists?(from p in Profile, where: p.group_id == ^group_id and p.published),
           do: Repo.rollback(:forbidden)

        current = Repo.get_by(Membership, group_id: group_id, user_id: scope.user.id)
        if current && current.revision != revision, do: Repo.rollback(:stale)

        if current && current.status not in ~w(pending withdrawn rejected removed),
          do: Repo.rollback(:withdraw_first)

        if current && current.external_removal_pending, do: Repo.rollback(:removal_pending)
        current = current || %Membership{group_id: group_id, user_id: scope.user.id}

        cs =
          current
          |> cast(attrs, [:display_name, :identifier])
          |> update_change(:display_name, &String.trim/1)
          |> update_change(:identifier, &String.downcase(String.trim(&1)))
          |> validate_required([:display_name])
          |> validate_length(:display_name, max: 100)
          |> validate_length(:identifier, max: 100)

        cs = if profile.whatsapp_enabled, do: validate_required(cs, [:identifier]), else: cs

        cs =
          if truthy?(attrs["conduct"]),
            do: cs,
            else: add_error(cs, :conduct_at, "acknowledge the conduct rules")

        cs =
          cs
          |> put_change(:status, "pending")
          |> put_change(:conduct_at, now())
          |> put_change(:matched_at, nil)
          |> put_change(:matched_by_id, nil)
          |> put_change(:code_hash, nil)
          |> put_change(:code_expires_at, nil)
          |> put_change(:code_attempts, 0)

        cs = if current.id, do: optimistic_lock(cs, :revision), else: cs

        case Repo.insert_or_update(cs) do
          {:ok, m} ->
            event(scope, group_id, m.id, "request", %{revision: m.revision})
            {:ok, applicant_view(m)}

          {:error, cs} ->
            {:error, cs}
        end
      end)
    end
  end

  def issue_reference(scope, group_id, revision) do
    with :ok <- confirmed(scope), true <- uuid?(group_id) do
      transaction(fn ->
        m =
          Repo.one(
            from m in Membership,
              where: m.group_id == ^group_id and m.user_id == ^scope.user.id,
              lock: "FOR UPDATE"
          )

        if !m || m.status != "pending" || m.revision != revision || confirmed(scope) != :ok,
          do: Repo.rollback(:stale)

        if m.code_issued_at && DateTime.diff(now(), m.code_issued_at) < 60,
          do: Repo.rollback(:cooldown)

        code = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
        expires = DateTime.add(now(), 900, :second)

        m =
          Repo.update!(
            change(m,
              code_hash: hash(code),
              code_issued_at: now(),
              code_expires_at: expires,
              code_attempts: 0,
              revision: m.revision + 1
            )
          )

        event(scope, group_id, m.id, "reference_issued", %{expires_at: expires})
        {:ok, %{membership: applicant_view(m), reference: code, expires_at: expires}}
      end)
    else
      _ -> {:error, :forbidden}
    end
  end

  def roster(scope, group_id) do
    with :ok <- manager(scope, group_id) do
      {:ok,
       Repo.all(
         from m in Membership, where: m.group_id == ^group_id, order_by: [desc: m.updated_at]
       )
       |> Enum.map(&Map.drop(Map.from_struct(&1), [:code_hash]))}
    end
  end

  def activity(scope, group_id) do
    with :ok <- manager(scope, group_id),
         do:
           {:ok,
            Repo.all(
              from e in Event,
                where: e.group_id == ^group_id,
                order_by: [desc: e.inserted_at],
                limit: 100
            )}
  end

  def match_reference(scope, group_id, id, code, revision) do
    manage(scope, group_id, id, revision, fn m ->
      valid =
        m.status == "pending" && m.code_hash && m.code_attempts < 5 && m.code_expires_at &&
          DateTime.compare(m.code_expires_at, now()) == :gt && is_binary(code) &&
          byte_size(code) <= 100 &&
          Plug.Crypto.secure_compare(m.code_hash, hash(String.trim(code)))

      if valid do
        m =
          Repo.update!(
            change(m,
              matched_at: now(),
              matched_by_id: scope.user.id,
              code_hash: nil,
              code_expires_at: nil,
              revision: m.revision + 1
            )
          )

        event(scope, group_id, m.id, "identifier_matched", %{
          method: "private_single_use_reference",
          revision: m.revision
        })

        {:ok, applicant_view(m)}
      else
        Repo.update!(change(m, code_attempts: min(m.code_attempts + 1, 5)))
        {:error, :invalid_reference}
      end
    end)
  end

  def decide(scope, group_id, id, action, attrs, revision)
      when action in [:approve, :admit, :reject, :suspend, :remove] do
    manage(scope, group_id, id, revision, fn m ->
      profile = Repo.get_by(Profile, group_id: group_id)

      if action == :approve && m.identifier &&
           Repo.exists?(
             from x in Membership,
               where:
                 x.group_id == ^group_id and x.id != ^id and x.identifier == ^m.identifier and
                   x.status in ["approved", "admitted"]
           ),
         do: Repo.rollback(:identifier_collision)

      context = %{
        actor: :manager,
        reason: attrs["reason"] || "",
        external_required: not is_nil(profile) and profile.whatsapp_enabled,
        matched: not is_nil(m.matched_at),
        observed_admission: truthy?(attrs["observed_admission"])
      }

      case PhoenixCommunity.Admission.transition(m.status, action, context) do
        {:ok, status} ->
          if action in [:suspend, :remove], do: revoke_role!(m)

          updated =
            Repo.update!(
              change(m,
                status: status,
                role: if(action in [:suspend, :remove], do: "member", else: m.role),
                external_removal_pending:
                  PhoenixCommunity.Admission.removal_pending?(
                    m.status,
                    status,
                    m.external_removal_pending
                  ),
                revision: m.revision + 1
              )
            )

          event(scope, group_id, id, to_string(action), %{
            from: m.status,
            to: status,
            reason: String.slice(attrs["reason"] || "", 0, 1000),
            revision: updated.revision
          })

          {:ok, applicant_view(updated)}

        error ->
          error
      end
    end)
  end

  def withdraw(scope, group_id, revision) do
    with :ok <- confirmed(scope), true <- uuid?(group_id) do
      transaction(fn ->
        if is_nil(Repo.one(from g in Group, where: g.id == ^group_id, lock: "FOR UPDATE")),
          do: Repo.rollback(:forbidden)

        m = Repo.get_by(Membership, group_id: group_id, user_id: scope.user.id)
        if !m || m.revision != revision || confirmed(scope) != :ok, do: Repo.rollback(:stale)

        case PhoenixCommunity.Admission.transition(m.status, :withdraw, %{actor: :applicant}) do
          {:ok, status} ->
            revoke_role!(m)

            updated =
              Repo.update!(
                change(m,
                  status: status,
                  role: "member",
                  code_hash: nil,
                  code_expires_at: nil,
                  external_removal_pending:
                    PhoenixCommunity.Admission.removal_pending?(
                      m.status,
                      status,
                      m.external_removal_pending
                    ),
                  revision: m.revision + 1
                )
              )

            event(scope, group_id, m.id, "withdraw", %{from: m.status, to: status})
            {:ok, applicant_view(updated)}

          error ->
            error
        end
      end)
    else
      _ -> {:error, :forbidden}
    end
  end

  def confirm_removal(scope, group_id, id, revision) do
    manage(scope, group_id, id, revision, fn m ->
      if !m.external_removal_pending, do: Repo.rollback(:invalid_transition)
      updated = Repo.update!(change(m, external_removal_pending: false, revision: m.revision + 1))
      event(scope, group_id, id, "external_removal_confirmed", %{revision: updated.revision})
      {:ok, applicant_view(updated)}
    end)
  end

  def delegate(scope, group_id, id, role, revision) when role in ~w(member coordinator manager) do
    manage(scope, group_id, id, revision, fn m ->
      if m.status not in ~w(approved admitted), do: Repo.rollback(:approval_required)
      user = Repo.get(User, m.user_id)
      if !user || !user.confirmed_at, do: Repo.rollback(:forbidden)

      if role == "manager" do
        Repo.insert!(change(%Manager{}, group_id: group_id, user_id: m.user_id),
          on_conflict: :nothing
        )
      else
        revoke_role!(m)
      end

      updated = Repo.update!(change(m, role: role, revision: m.revision + 1))

      event(scope, group_id, id, "delegate", %{from: m.role, to: role, revision: updated.revision})

      {:ok, applicant_view(updated)}
    end)
  end

  def invitation(scope, group_id) do
    with :ok <- confirmed(scope),
         true <- uuid?(group_id),
         %Membership{status: status, matched_at: matched_at, external_removal_pending: false} <-
           Repo.get_by(Membership, group_id: group_id, user_id: scope.user.id),
         true <- status in ~w(approved admitted) and not is_nil(matched_at),
         %Profile{whatsapp_enabled: true, whatsapp_approval_confirmed: true} = p <-
           Repo.get_by(Profile, group_id: group_id) do
      {:ok, p.whatsapp_invite_url}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp manage(scope, group_id, id, revision, fun) do
    with :ok <- manager(scope, group_id), true <- uuid?(id) do
      transaction(fn ->
        lock_group!(scope, group_id)
        m = Repo.get_by(Membership, id: id, group_id: group_id)
        if !m || m.revision != revision, do: Repo.rollback(:stale)
        fun.(m)
      end)
    else
      _ -> {:error, :forbidden}
    end
  end

  defp revoke_role!(m) do
    if Repo.exists?(
         from x in Manager, where: x.group_id == ^m.group_id and x.user_id == ^m.user_id
       ) do
      remaining =
        Repo.aggregate(
          from(x in Manager,
            join: u in User,
            on: u.id == x.user_id,
            where:
              x.group_id == ^m.group_id and x.user_id != ^m.user_id and not is_nil(u.confirmed_at)
          ),
          :count
        )

      if remaining == 0, do: Repo.rollback(:last_manager)

      Repo.delete_all(
        from x in Manager, where: x.group_id == ^m.group_id and x.user_id == ^m.user_id
      )
    end
  end

  defp manager(scope, group_id) do
    if uuid?(group_id) && confirmed(scope) == :ok &&
         Enum.any?(Volunteers.groups(scope), &(&1.id == group_id)),
       do: :ok,
       else: {:error, :forbidden}
  end

  defp confirmed(%Scope{user: %{id: id}}) do
    if Repo.exists?(from u in User, where: u.id == ^id and not is_nil(u.confirmed_at)),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp confirmed(_), do: {:error, :forbidden}

  defp lock_group!(scope, id) do
    if is_nil(Repo.one(from g in Group, where: g.id == ^id, lock: "FOR UPDATE")),
      do: Repo.rollback(:forbidden)

    if manager(scope, id) != :ok, do: Repo.rollback(:forbidden)
  end

  defp event(scope, group, membership, action, details),
    do:
      Repo.insert!(%Event{
        group_id: group,
        membership_id: membership,
        actor_id: scope.user.id,
        action: action,
        details: details
      })

  defp transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, result} -> result
      {:error, error} -> {:error, error}
    end
  end

  defp applicant_view(m),
    do:
      Map.take(
        m,
        ~w(id group_id display_name identifier status role matched_at external_removal_pending revision)a
      )

  defp now, do: DateTime.utc_now()
  defp hash(value), do: :crypto.hash(:sha256, value)
  defp uuid?(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp blank?(value), do: value in [nil, ""]
  defp truthy?(value), do: value in [true, "true", "on"]

  defp parse_fsas(value) when is_binary(value),
    do: value |> String.upcase() |> String.split(~r/[\s,;]+/, trim: true) |> Enum.uniq()

  defp parse_fsas(value) when is_list(value),
    do: value |> Enum.map(&String.upcase(String.trim(&1))) |> Enum.uniq()

  defp parse_fsas(_), do: []

  defp validate_url(cs, field),
    do:
      validate_change(cs, field, fn key, value ->
        case URI.parse(value) do
          %URI{scheme: "https", host: host, userinfo: nil} when is_binary(host) and host != "" ->
            []

          _ ->
            [{key, "use an HTTPS URL"}]
        end
      end)
end
