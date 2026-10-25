defmodule PauseAiCa.Tasks.Event do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "organizer_task_events" do
    belongs_to :group, PauseAiCa.Volunteers.Group
    belongs_to :task, PauseAiCa.Tasks.Task
    belongs_to :actor, PauseAiCa.Accounts.User
    field :command_id, :string
    field :fingerprint, :binary
    field :action, :string
    field :revision, :integer
    field :details, :map, default: %{}
    field :result, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
