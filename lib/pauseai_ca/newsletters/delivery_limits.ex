defmodule PauseAiCa.Newsletters.DeliveryLimits do
  @moduledoc "Append-only, administrator-attributed rolling-hour delivery policy."
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}

  schema "newsletter_delivery_limits" do
    field :personal, :integer, default: 20
    field :global, :integer, default: 100
    field :actor_id, :binary_id
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def current,
    do: Repo.one(from l in __MODULE__, order_by: [desc: l.id], limit: 1) || %__MODULE__{}

  def get(scope) do
    if Volunteers.superadmin?(scope), do: {:ok, current()}, else: {:error, :unauthorized}
  end

  def changeset(limits, attrs) do
    limits
    |> cast(attrs, [:personal, :global])
    |> validate_required([:personal, :global])
    |> validate_number(:personal, greater_than: 0, less_than_or_equal_to: 100_000)
    |> validate_number(:global, greater_than: 0, less_than_or_equal_to: 100_000)
    |> then(fn cs ->
      if is_integer(get_field(cs, :personal)) and is_integer(get_field(cs, :global)) and
           get_field(cs, :personal) > get_field(cs, :global),
         do:
           add_error(cs, :personal, "must be less than or equal to %{number}",
             number: get_field(cs, :global)
           ),
         else: cs
    end)
  end

  def save(scope, revision, attrs) do
    Repo.transaction(fn ->
      unless Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)
      # Serialize policy changes with the exact lock used for delivery reservations.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext('pauseai-newsletter-delivery-quota'))")

      actor =
        Repo.one(
          from u in PauseAiCa.Accounts.User, where: u.id == ^scope.user.id, lock: "FOR UPDATE"
        )

      unless actor && actor.superadmin && actor.confirmed_at, do: Repo.rollback(:unauthorized)
      latest = current()
      if to_string(latest.id || 0) != to_string(revision), do: Repo.rollback(:stale)

      case %__MODULE__{actor_id: actor.id} |> changeset(attrs) |> Repo.insert() do
        {:ok, saved} -> saved
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end
end
