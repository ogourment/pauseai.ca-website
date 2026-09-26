defmodule PauseAiCa.AccountManagement do
  @moduledoc "Account administration within the organizer's current group permissions."
  import Ecto.Query
  import Ecto.Changeset
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.User
  alias PauseAiCa.Volunteers.{Event, Group, Input, Signup}

  def list(scope, search \\ "", page \\ 1) do
    term = "%#{String.trim(search)}%"

    query(scope)
    |> where([u], ilike(u.email, ^term) or ilike(u.name, ^term))
    |> order_by([u], asc: u.email)
    |> offset(^((max(page, 1) - 1) * 25))
    |> limit(26)
    |> select([u, s, g], %{user: u, signup: s, group: g})
    |> Repo.all()
  end

  def get(scope, id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         record when not is_nil(record) <-
           query(scope)
           |> where([u], u.id == ^id)
           |> select([u, s, g], %{user: u, signup: s, group: g})
           |> Repo.one() do
      {:ok,
       Map.update!(record, :signup, fn signup ->
         if signup, do: Repo.preload(signup, :invitations)
       end)}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def update(scope, id, attrs) do
    Repo.transaction(fn ->
      case get(scope, id) do
        {:ok, %{user: user, signup: signup}} ->
          row =
            Input.normalize(
              Map.merge(
                %{
                  "name" => user.name || "",
                  "postal_code" => user.postal_code || "",
                  "city" => user.city || "",
                  "email" => user.email
                },
                Map.take(attrs, ~w(name postal_code city notes))
              )
            )

          errors = Input.errors(row)

          errors =
            if String.length(row["name"]) > 160,
              do: Map.put(errors, "name", :too_long),
              else: errors

          if errors != %{}, do: Repo.rollback(errors)

          changes = %{
            name: row["name"],
            postal_code: row["postal_code"],
            city: row["city"],
            fsa: if(row["postal_code"] != "", do: String.slice(row["postal_code"], 0, 3))
          }

          updated = user |> change(changes) |> Repo.update!()

          if signup && Map.has_key?(attrs, "notes"),
            do: signup |> change(notes: row["notes"]) |> Repo.update!()

          Repo.insert!(%Event{
            actor_id: scope.user.id,
            batch_id: signup && signup.batch_id,
            signup_id: signup && signup.id,
            action: "account_updated",
            details: %{"user_id" => id}
          })

          updated

        _ ->
          Repo.rollback(:unauthorized)
      end
    end)
  end

  defp query(scope) do
    base =
      from u in User,
        left_join: s in Signup,
        on: s.user_id == u.id,
        left_join: g in Group,
        on: g.id == s.group_id

    if Volunteers.superadmin?(scope) do
      base
    else
      ids = Enum.map(Volunteers.groups(scope), & &1.id)
      from [u, s, g] in base, where: s.group_id in ^ids
    end
  end
end
