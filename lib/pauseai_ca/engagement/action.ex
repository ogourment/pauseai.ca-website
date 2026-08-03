defmodule PauseAiCa.Engagement.Action do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "actions" do
    field :action_type, :string
    field :happened_on, :date
    field :notes, :string
    field :location, :string
    field :quantity, :integer
    field :confirmed_at, :utc_datetime
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @action_types ~w(
    learned
    conversation
    event
    contacted_representative
    met_representative
    joined
    signed
    flyered
    volunteered
    organized
    other
  )

  # Which extra fields an action type can carry. Asking a reader how many
  # people attended their reading would be silly; not asking an organiser
  # wastes the record.
  @with_location ~w(event met_representative flyered volunteered organized)
  @with_quantity ~w(event flyered organized conversation)

  def action_types, do: @action_types

  @doc "True when `type` can sensibly carry a place."
  def location?(type), do: type in @with_location

  @doc "True when `type` can sensibly carry a count."
  def quantity?(type), do: type in @with_quantity

  @doc false
  # True when we do not yet know whether the action actually happened. A letter
  # opened in someone's own mail client is the case this exists for: we handed
  # it over, and only they know whether they pressed send.
  def pending?(%__MODULE__{confirmed_at: nil}), do: true
  def pending?(%__MODULE__{}), do: false

  # Someone who picks "organized", fills in a count, then switches to "learned"
  # should not silently keep the count.
  defp drop_irrelevant_detail(changeset) do
    type = get_field(changeset, :action_type)

    changeset
    |> then(fn cs -> if location?(type), do: cs, else: put_change(cs, :location, nil) end)
    |> then(fn cs -> if quantity?(type), do: cs, else: put_change(cs, :quantity, nil) end)
  end

  @doc false
  def confirm_changeset(action) do
    change(action, confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc false
  def changeset(action, attrs, user_scope) do
    action
    |> cast(attrs, [
      :action_type,
      :happened_on,
      :notes,
      :location,
      :quantity,
      :confirmed_at
    ])
    |> validate_required([:action_type, :happened_on])
    |> validate_inclusion(:action_type, @action_types)
    |> validate_length(:notes, max: 500)
    |> validate_length(:location, max: 200)
    |> validate_number(:quantity, greater_than_or_equal_to: 0, less_than: 1_000_000)
    |> drop_irrelevant_detail()
    |> put_change(:user_id, user_scope.user.id)
  end
end
