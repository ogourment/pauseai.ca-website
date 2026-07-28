defmodule PauseAiCa.Engagement.Action do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "actions" do
    field :action_type, :string
    field :happened_on, :date
    field :notes, :string
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
  def changeset(action, attrs, user_scope) do
    action
    |> cast(attrs, [:action_type, :happened_on, :notes])
    |> validate_required([:action_type, :happened_on])
    |> validate_inclusion(:action_type, @action_types)
    |> validate_length(:notes, max: 500)
    |> put_change(:user_id, user_scope.user.id)
  end
end
