defmodule PauseAiCa.Engagement.Action do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "actions" do
    field :action_type, :string
    field :happened_on, :date
    field :notes, :string
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
    volunteered
    organized
    other
  )

  def action_types, do: @action_types

  @doc false
  # True when we do not yet know whether the action actually happened. A letter
  # opened in someone's own mail client is the case this exists for: we handed
  # it over, and only they know whether they pressed send.
  def pending?(%__MODULE__{confirmed_at: nil}), do: true
  def pending?(%__MODULE__{}), do: false

  @doc false
  def confirm_changeset(action) do
    change(action, confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc false
  def changeset(action, attrs, user_scope) do
    action
    |> cast(attrs, [:action_type, :happened_on, :notes, :confirmed_at])
    |> validate_required([:action_type, :happened_on])
    |> validate_inclusion(:action_type, @action_types)
    |> validate_length(:notes, max: 500)
    |> put_change(:user_id, user_scope.user.id)
  end
end
