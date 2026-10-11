defmodule PauseAiCa.Newsletters.Drafts do
  @moduledoc "Private author drafts with fresh superadmin checks, reversible archive and optimistic revisions."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers, Accounts.User}
  alias PauseAiCa.Newsletters.Draft

  def list(scope, archived? \\ false) do
    if Volunteers.superadmin?(scope) do
      query =
        from d in Draft,
          where: d.owner_id == ^scope.user.id,
          order_by: [desc: d.updated_at, desc: d.id]

      query =
        if archived?,
          do: from(d in query, where: not is_nil(d.archived_at)),
          else: from(d in query, where: is_nil(d.archived_at))

      {:ok, Repo.all(query)}
    else
      {:error, :unauthorized}
    end
  end

  def get(scope, id) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %Draft{} = draft <-
           Repo.one(from d in Draft, where: d.id == ^uuid and d.owner_id == ^scope.user.id) do
      {:ok, draft}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def create(scope) do
    authorized(scope, fn -> Repo.insert!(%Draft{owner_id: scope.user.id}) end)
  end

  def create_for_list(scope, list_id) do
    authorized(scope, fn ->
      case PauseAiCa.Newsletters.Lists.get(scope, list_id) do
        {:ok, %{archived_at: nil} = list} ->
          Repo.insert!(%Draft{
            owner_id: scope.user.id,
            recipient_mode: "list",
            mailing_list_id: list.id
          })

        _ ->
          Repo.rollback(:audience_required)
      end
    end)
  end

  def save(scope, %Draft{} = expected, attrs) do
    authorized(scope, fn ->
      draft = locked(scope, expected)
      if draft.archived_at, do: Repo.rollback(:archived)
      changeset = draft |> Draft.changeset(attrs)

      changeset =
        if Ecto.Changeset.get_field(changeset, :recipient_mode) == "list" do
          case PauseAiCa.Newsletters.Lists.get(
                 scope,
                 Ecto.Changeset.get_field(changeset, :mailing_list_id)
               ) do
            {:ok, %{archived_at: nil}} -> changeset
            _ -> Ecto.Changeset.add_error(changeset, :mailing_list_id, "is invalid")
          end
        else
          Ecto.Changeset.put_change(changeset, :mailing_list_id, nil)
        end

      changeset = changeset |> Ecto.Changeset.optimistic_lock(:revision)

      case Repo.update(changeset) do
        {:ok, saved} -> saved
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def archive(scope, %Draft{} = expected, archive? \\ true) do
    authorized(scope, fn ->
      locked(scope, expected)
      |> Ecto.Changeset.change(archived_at: if(archive?, do: DateTime.utc_now(), else: nil))
      |> Ecto.Changeset.optimistic_lock(:revision)
      |> Repo.update!()
    end)
  end

  defp locked(scope, expected) do
    draft =
      Repo.one(
        from d in Draft,
          where: d.id == ^expected.id and d.owner_id == ^scope.user.id,
          lock: "FOR UPDATE"
      )

    if is_nil(draft), do: Repo.rollback(:unauthorized)
    if draft.revision != expected.revision, do: Repo.rollback(:stale)
    draft
  end

  defp authorized(scope, fun) do
    if Volunteers.superadmin?(scope) do
      Repo.transaction(fn ->
        Repo.one(from u in User, where: u.id == ^scope.user.id, lock: "FOR UPDATE")
        if not Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)
        fun.()
      end)
    else
      {:error, :unauthorized}
    end
  end
end
