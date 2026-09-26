defmodule PauseAiCa.Volunteers.Manager do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "volunteer_group_managers" do
    belongs_to :group, PauseAiCa.Volunteers.Group
    belongs_to :user, PauseAiCa.Accounts.User
    timestamps(type: :utc_datetime)
  end
end
