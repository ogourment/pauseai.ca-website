defmodule PauseAiCa.Volunteers.Invitation do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "volunteer_invitations" do
    belongs_to :signup, PauseAiCa.Volunteers.Signup
    belongs_to :actor, PauseAiCa.Accounts.User
    field :status, :string, default: "queued"
    field :provider_id, :string
    field :attempted_at, :utc_datetime
    field :completed_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
