defmodule PauseAiCa.Newsletters.RecipientExport do
  @moduledoc "Admin-owned prepared batch recipient snapshots; exporting never approves or sends."
  import Ecto.Query
  alias PauseAiCa.{Accounts, CSV, Repo}
  alias PauseAiCa.Newsletters.{Batch, Delivery}

  def download(%Accounts.Scope{user: %{id: actor_id}}, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      Repo.transaction(fn ->
        # Keep revocation from racing the read; never trust the scope's role snapshot.
        actor =
          Repo.one(
            from(u in Accounts.User,
              where: u.id == ^actor_id and u.superadmin == true and not is_nil(u.confirmed_at),
              lock: "FOR SHARE"
            )
          )

        unless actor, do: Repo.rollback(:unauthorized)

        unless Repo.exists?(from(b in Batch, where: b.id == ^uuid and b.owner_id == ^actor_id)),
          do: Repo.rollback(:unauthorized)

        emails =
          Repo.all(
            from(d in Delivery,
              where: d.batch_id == ^uuid,
              order_by: [asc: d.email, asc: d.id],
              select: d.email
            )
          )

        %{
          filename: "batch-#{uuid}-recipients.csv",
          content: CSV.encode([["email"] | Enum.map(emails, &[&1])])
        }
      end)
    else
      _ -> {:error, :unauthorized}
    end
  end

  def download(_, _), do: {:error, :unauthorized}
end
