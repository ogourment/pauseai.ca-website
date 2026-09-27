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

  def count(scope, search \\ "") do
    term = "%#{String.trim(search)}%"

    query(scope)
    |> where([u], ilike(u.email, ^term) or ilike(u.name, ^term))
    |> Repo.aggregate(:count, :id)
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
          Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")
          # Re-evaluate scope after obtaining the row lock.
          if match?({:error, _}, get(scope, id)), do: Repo.rollback(:unauthorized)
          user = Repo.get!(User, id)
          destination = Map.get(attrs, "group_id", user.organizing_group_id)
          destination = if destination == "", do: nil, else: destination

          valid_group? =
            if is_nil(destination),
              do: Volunteers.superadmin?(scope),
              else: Enum.any?(Volunteers.groups(scope), &(&1.id == destination))

          if not valid_group?, do: Repo.rollback(%{"group_id" => :unauthorized_group})

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
            organizing_group_id: destination,
            organizer_notes:
              if(Map.has_key?(attrs, "notes"), do: row["notes"], else: user.organizer_notes),
            name: row["name"],
            postal_code: row["postal_code"],
            city: row["city"],
            fsa: if(row["postal_code"] != "", do: String.slice(row["postal_code"], 0, 3))
          }

          updated = user |> change(changes) |> Repo.update!()

          if signup,
            do:
              signup
              |> change(group_id: destination, notes: updated.organizer_notes)
              |> Repo.update!()

          Repo.insert!(%Event{
            actor_id: scope.user.id,
            batch_id: signup && signup.batch_id,
            signup_id: signup && signup.id,
            action: "account_updated",
            details: %{
              "user_id" => id,
              "old_group_id" => user.organizing_group_id,
              "new_group_id" => destination
            }
          })

          updated

        _ ->
          Repo.rollback(:unauthorized)
      end
    end)
  end

  def set_superadmin(scope, id, value) when is_boolean(value) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(349819)")
      if not Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)

      with {:ok, %{user: target}} <- get(scope, id) do
        actor = Repo.get!(User, scope.user.id)

        case PauseAiCa.Accounts.set_superadmin(actor, target, value) do
          {:ok, user} ->
            changed = target.superadmin != user.superadmin

            if changed,
              do:
                Repo.insert!(%Event{
                  actor_id: actor.id,
                  action: "account_role_changed",
                  details: %{"user_id" => id, "superadmin" => value}
                })

            {user, changed}

          {:error, reason} ->
            Repo.rollback(reason)
        end
      else
        _ -> Repo.rollback(:unauthorized)
      end
    end)
  end

  defp query(scope) do
    base =
      from u in User,
        left_join: s in Signup,
        on: s.user_id == u.id,
        left_join: g in Group,
        on: g.id == u.organizing_group_id

    if Volunteers.superadmin?(scope) do
      base
    else
      ids = Enum.map(Volunteers.groups(scope), & &1.id)
      from [u, s, g] in base, where: u.organizing_group_id in ^ids
    end
  end
end
