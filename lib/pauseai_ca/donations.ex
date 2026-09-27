defmodule PauseAiCa.Donations do
  @moduledoc "Promises of support only: no payment, account, subscription or automatic mail."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Donations.Pledge

  def change(attrs \\ %{}), do: Pledge.changeset(%Pledge{}, attrs)

  def pledge(attrs) do
    if (attrs["website"] || "") != "" do
      {:ok, :recorded}
    else
      changeset = change(attrs)
      email = Ecto.Changeset.get_field(changeset, :email)

      if changeset.valid? do
        Repo.transaction(fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(349820)")

          case Repo.get_by(Pledge, email: email) do
            nil ->
              since = DateTime.add(DateTime.utc_now(), -3600)

              if Repo.aggregate(from(p in Pledge, where: p.inserted_at >= ^since), :count) >= 200,
                do: Repo.rollback(:rate_limited)

              changeset
              |> Ecto.Changeset.put_change(:consented_at, DateTime.utc_now(:second))
              |> Repo.insert!()

              :recorded

            _ ->
              :recorded
          end
        end)
      else
        {:error, %{changeset | action: :insert}}
      end
    end
  end

  def list(scope, page \\ 1) do
    if Volunteers.superadmin?(scope),
      do:
        {:ok,
         Repo.all(
           from p in Pledge,
             order_by: [desc: p.inserted_at, desc: p.id],
             limit: 26,
             offset: ^((max(page, 1) - 1) * 25)
         )},
      else: {:error, :unauthorized}
  end
end
