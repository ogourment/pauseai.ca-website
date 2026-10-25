defmodule PauseAiCa.Welcome.Event do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "welcome_events" do
    belongs_to :group, PauseAiCa.Volunteers.Group
    belongs_to :session, PauseAiCa.Welcome.Session
    belongs_to :participant, PauseAiCa.Welcome.Participant
    belongs_to :actor, PauseAiCa.Accounts.User
    field :action, :string
    field :command_id, :string
    field :fingerprint, :binary
    field :result_kind, :string
    field :result_id, :binary_id
    field :details, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
