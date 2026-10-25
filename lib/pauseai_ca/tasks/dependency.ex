defmodule PauseAiCa.Tasks.Dependency do
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "organizer_task_dependencies" do
    belongs_to :group, PauseAiCa.Volunteers.Group
    belongs_to :task, PauseAiCa.Tasks.Task, primary_key: true
    belongs_to :prerequisite, PauseAiCa.Tasks.Task, primary_key: true
  end
end
