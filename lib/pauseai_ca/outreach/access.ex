defmodule PauseAiCa.Outreach.Access do
  @moduledoc "Fresh local account/group eligibility and audited per-mailbox delegation."
  import Ecto.Query
  alias PauseAiCa.{Accounts, Repo, Volunteers}
  alias PauseAiCa.Accounts.{Scope, User}
  alias PauseAiCa.Outreach.{MailboxGrant, MailboxGrantEvent, Mailboxes}
  alias PauseAiCa.Volunteers.Manager
  alias PhoenixMailWorkflow.MailboxAccess

  def facts(scope, lock? \\ false)

  def facts(%Scope{user: %{id: id}}, lock?) when is_binary(id) do
    {user, generation} =
      Repo.one(
        maybe_lock(
          from(u in User,
            where: u.id == ^id,
            select: {u, fragment("xmin::text")}
          ),
          lock?
        )
      ) || {nil, nil}

    managers =
      Repo.all(maybe_lock(from(m in Manager, where: m.user_id == ^id, order_by: m.id), lock?))

    grants = Repo.all(maybe_lock(from(g in MailboxGrant, where: g.user_id == ^id), lock?))

    %{
      actor_id: id,
      confirmed?: not is_nil(user) and not is_nil(user.confirmed_at),
      full_access?: not is_nil(user) and user.superadmin,
      eligible?: managers != [],
      eligibility_stamp:
        {generation, if(user, do: user.updated_at), if(user, do: user.confirmed_at),
         Enum.map(managers, & &1.id)},
      grants: grants
    }
  end

  def facts(_, _), do: %{confirmed?: false}

  def eligible?(scope) do
    case facts(scope) do
      %{confirmed?: true, full_access?: true} -> true
      %{confirmed?: true, eligible?: true} -> true
      _ -> false
    end
  end

  def allowed?(scope, ref), do: MailboxAccess.allowed?(facts(scope), ref)
  def fingerprint(scope, ref), do: MailboxAccess.fingerprint(facts(scope), ref)
  def covers?(scope, refs, complete?), do: MailboxAccess.covers?(facts(scope), refs, complete?)

  def lock!(scope, ref) do
    authorization = facts(scope, true)

    case MailboxAccess.fingerprint(authorization, ref) do
      {:ok, fingerprint} -> fingerprint
      _ -> Repo.rollback(:unauthorized)
    end
  end

  def management(scope) do
    if Volunteers.superadmin?(scope) do
      managers =
        Repo.all(
          from(u in User,
            join: m in Manager,
            on: m.user_id == u.id,
            where: not is_nil(u.confirmed_at),
            distinct: true,
            order_by: [u.name, u.email],
            select: %{id: u.id, name: u.name, email: u.email}
          )
        )

      eligible_ids = MapSet.new(managers, & &1.id)

      grants =
        Repo.all(
          from(g in MailboxGrant, preload: [:user], order_by: [g.mailbox_ref, g.inserted_at])
        )

      rows =
        Enum.map(grants, fn grant ->
          Map.take(grant, [:id, :mailbox_ref, :user_id, :revision, :granted_at, :revoked_at])
          |> Map.put(:user, %{
            id: grant.user.id,
            name: grant.user.name,
            email: grant.user.email,
            eligible?: MapSet.member?(eligible_ids, grant.user_id)
          })
        end)

      {:ok, %{mailboxes: Mailboxes.configured(), eligible_managers: managers, grants: rows}}
    else
      {:error, :unauthorized}
    end
  end

  def grant(scope, ref, user_id, revision), do: change(scope, ref, user_id, revision, :grant)
  def revoke(scope, ref, user_id, revision), do: change(scope, ref, user_id, revision, :revoke)

  defp change(scope, ref, user_id, revision, action) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, user_id} <- Ecto.UUID.cast(user_id),
         true <- is_integer(revision) and revision >= 0,
         true <- Enum.any?(Mailboxes.configured(), &(&1.id == ref)) do
      Repo.transaction(fn ->
        Repo.all(
          from(u in User,
            where: u.id in ^[scope.user.id, user_id],
            order_by: u.id,
            lock: "FOR UPDATE"
          )
        )

        if not Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)
        target = Accounts.Scope.for_user(Repo.get(User, user_id))
        if is_nil(target), do: Repo.rollback(:not_eligible)
        target_facts = facts(target, true)

        if action == :grant and not (target_facts.confirmed? and target_facts.eligible?),
          do: Repo.rollback(:not_eligible)

        current = Repo.get_by(MailboxGrant, mailbox_ref: ref, user_id: user_id)
        if if(current, do: current.revision, else: 0) != revision, do: Repo.rollback(:stale)
        persist(scope, ref, user_id, current, action)
      end)
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp persist(_scope, _ref, _id, %{revoked_at: nil} = current, :grant), do: current

  defp persist(_scope, _ref, _id, %{revoked_at: revoked} = current, :revoke)
       when not is_nil(revoked), do: current

  defp persist(_scope, _ref, _id, nil, :revoke), do: Repo.rollback(:stale)

  defp persist(scope, ref, id, current, action) do
    now = DateTime.utc_now()
    grant = current || %MailboxGrant{mailbox_ref: ref, user_id: id, revision: 0}

    attrs =
      if action == :grant,
        do: %{granted_at: now, granted_by_id: scope.user.id, revoked_at: nil, revoked_by_id: nil},
        else: %{revoked_at: now, revoked_by_id: scope.user.id}

    grant =
      grant
      |> Ecto.Changeset.change(Map.put(attrs, :revision, grant.revision + 1))
      |> Repo.insert_or_update!()

    Repo.insert!(%MailboxGrantEvent{
      grant_id: grant.id,
      actor_id: scope.user.id,
      action: if(action == :grant, do: "granted", else: "revoked"),
      revision: grant.revision
    })

    grant
  end

  defp maybe_lock(query, true), do: from(row in query, lock: "FOR UPDATE")
  defp maybe_lock(query, false), do: query
end
