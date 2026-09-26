defmodule PauseAiCa.Volunteers.Event do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "volunteer_events" do
    belongs_to :batch, PauseAiCa.Volunteers.Batch
    belongs_to :signup, PauseAiCa.Volunteers.Signup
    belongs_to :actor, PauseAiCa.Accounts.User
    field :action, :string
    field :details, :map, default: %{}
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
