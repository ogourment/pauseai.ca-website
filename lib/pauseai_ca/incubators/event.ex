defmodule PauseAiCa.Incubators.Event do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "incubator_membership_events" do
    field :group_id, :binary_id
    field :membership_id, :binary_id
    field :actor_id, :binary_id
    field :action, :string
    field :details, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
