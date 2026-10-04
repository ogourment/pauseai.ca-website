defmodule PauseAiCa.Mail do
  @moduledoc "Consumer-owned private drafts. Eligibility authorizes preparation only, never delivery."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers, AccountManagement}
  alias PauseAiCa.Accounts.User
  alias PauseAiCa.ContactMigration.Contact
  alias PauseAiCa.CRM.ContactLink
  alias PhoenixCRM.{Person, Address}
  alias PauseAiCa.Mail.{Batch, Draft, Render}

  def recipient(scope, id) do
    with {:ok, %{user: %{confirmed_at: at} = user}} when not is_nil(at) <-
           AccountManagement.get(scope, id),
         false <- suppressed?(user.email) do
      {:ok,
       %{
         id: user.id,
         name: user.name || "",
         email: user.email,
         variables: %{"name" => user.name || "", "email" => user.email, "city" => user.city || ""}
       }}
    else
      true -> {:error, :ineligible}
      {:ok, _} -> {:error, :ineligible}
      _ -> {:error, :unauthorized}
    end
  end

  def list(scope) do
    if Volunteers.allowed?(scope),
      do:
        Repo.all(
          from b in Batch,
            where: b.owner_id == ^scope.user.id,
            order_by: [desc: b.updated_at, desc: b.id]
        ),
      else: []
  end

  def get(scope, id) do
    with true <- Volunteers.allowed?(scope),
         {:ok, _} <- Ecto.UUID.cast(id),
         %Batch{} = batch <- Repo.get_by(Batch, id: id, owner_id: scope.user.id),
         :ok <- recipients_allowed(scope, workspace_ids(batch)) do
      {:ok, batch}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def create(scope, account_id) do
    transact(fn ->
      lock_actor(scope)

      case recipient(scope, account_id) do
        {:ok, _} ->
          Repo.insert!(%Batch{
            owner_id: scope.user.id,
            anchor_user_id: account_id,
            recipient_ids: [account_id]
          })

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def save_batch(scope, %Batch{} = batch, attrs) do
    transact(fn ->
      stored = lock_batch(scope, batch.id)
      if stored.revision != batch.revision, do: Repo.rollback(:stale)
      cs = Batch.changeset(stored, attrs)
      ids = Ecto.Changeset.get_field(cs, :recipient_ids) |> Enum.uniq()
      cs = Ecto.Changeset.put_change(cs, :recipient_ids, ids)
      require_allowed(scope, ids)

      case Repo.update(cs, stale_error_field: :revision) do
        {:ok, saved} -> saved
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  def drafts(scope, batch_id) do
    with {:ok, _} <- get(scope, batch_id) do
      {:ok, Repo.all(from d in Draft, where: d.batch_id == ^batch_id, order_by: d.id)}
    end
  end

  def save_draft(scope, %Draft{} = draft, attrs) do
    transact(fn ->
      lock_batch(scope, draft.batch_id)

      stored =
        Repo.one(
          from d in Draft,
            where: d.id == ^draft.id and d.batch_id == ^draft.batch_id,
            lock: "FOR UPDATE"
        )

      if is_nil(stored) or stored.revision != draft.revision, do: Repo.rollback(:stale)

      case recipient(scope, stored.user_id) do
        {:ok, contact} when contact.email == stored.email -> :ok
        _ -> Repo.rollback(:unauthorized)
      end

      case stored |> Draft.changeset(attrs) |> Repo.update(stale_error_field: :revision) do
        {:ok, saved} -> saved
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  def generate(scope, batch_id) do
    transact(fn ->
      batch = lock_batch(scope, batch_id)
      if length(batch.recipient_ids) not in 1..5, do: Repo.rollback(:batch_size)

      Enum.map(batch.recipient_ids, fn id ->
        case Repo.get_by(Draft, batch_id: batch.id, user_id: id) do
          %Draft{} = draft ->
            draft

          nil ->
            {:ok, contact} = recipient(scope, id)

            with {:ok, subject} <- Render.merge(batch.subject, contact.variables),
                 {:ok, source} <- Render.merge(batch.source, contact.variables) do
              cs =
                Draft.changeset(
                  %Draft{
                    batch_id: batch.id,
                    user_id: id,
                    email: contact.email,
                    name: contact.name,
                    variables: contact.variables
                  },
                  %{subject: subject, source: source}
                )

              case Repo.insert(cs) do
                {:ok, draft} -> draft
                {:error, error} -> Repo.rollback(error)
              end
            else
              {:error, missing} -> Repo.rollback({:missing_variables, missing})
            end
        end
      end)
    end)
  end

  # A withdrawal on any originating historical contact blocks all aliases. Never switch address to bypass it.
  @doc "Consumer-owned historical withdrawal guard, shared with newsletter eligibility."
  def suppressed?(email) do
    direct =
      Repo.exists?(
        from c in Contact, where: c.email == ^email and c.classification == "do_not_contact"
      )

    canonical =
      Repo.one(
        from a in Address,
          join: p in Person,
          on: p.id == a.person_id,
          where: a.email == ^email,
          select: coalesce(p.canonical_id, p.id)
      )

    direct or
      (not is_nil(canonical) and
         Repo.exists?(
           from c in Contact,
             join: l in ContactLink,
             on: c.id == l.contact_id,
             join: p in Person,
             on: p.id == l.person_id,
             where:
               (p.id == ^canonical or p.canonical_id == ^canonical) and
                 c.classification == "do_not_contact"
         ))
  end

  @doc "Batch historical withdrawal lookup for audience review; same canonical alias policy as recipient preparation."
  def suppressed_emails(emails) do
    direct =
      Repo.all(
        from c in Contact,
          where: c.email in ^emails and c.classification == "do_not_contact",
          select: c.email
      )

    linked =
      Repo.all(
        from a in Address,
          join: p in Person,
          on: p.id == a.person_id,
          join: origin in Person,
          on: coalesce(origin.canonical_id, origin.id) == coalesce(p.canonical_id, p.id),
          join: link in ContactLink,
          on: link.person_id == origin.id,
          join: c in Contact,
          on: c.id == link.contact_id,
          where: a.email in ^emails and c.classification == "do_not_contact",
          select: a.email,
          distinct: true
      )

    MapSet.new(direct ++ linked)
  end

  defp workspace_ids(batch) do
    saved = Repo.all(from d in Draft, where: d.batch_id == ^batch.id, select: d.user_id)
    Enum.uniq(batch.recipient_ids ++ saved)
  end

  defp recipients_allowed(scope, ids) do
    if ids != [] and Enum.all?(ids, &match?({:ok, _}, recipient(scope, &1))),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp require_allowed(scope, ids),
    do: if(recipients_allowed(scope, ids) != :ok, do: Repo.rollback(:unauthorized))

  defp lock_actor(%{user: %{id: id}} = scope) do
    Repo.one!(from u in User, where: u.id == ^id, lock: "FOR UPDATE")

    Repo.all(
      from m in PauseAiCa.Volunteers.Manager,
        where: m.user_id == ^id,
        order_by: m.id,
        lock: "FOR SHARE"
    )

    if not Volunteers.allowed?(scope), do: Repo.rollback(:unauthorized)
  end

  defp lock_batch(scope, id) do
    lock_actor(scope)

    with {:ok, _} <- Ecto.UUID.cast(id),
         %Batch{} = batch <-
           Repo.one(
             from b in Batch,
               where: b.id == ^id and b.owner_id == ^scope.user.id,
               lock: "FOR UPDATE"
           ) do
      # Lock current recipient/group assignments before the final scope check.
      Repo.all(
        from u in User, where: u.id in ^batch.recipient_ids, order_by: u.id, lock: "FOR UPDATE"
      )

      require_allowed(scope, workspace_ids(batch))
      batch
    else
      _ -> Repo.rollback(:unauthorized)
    end
  end

  defp transact(fun), do: Repo.transaction(fun)
end
