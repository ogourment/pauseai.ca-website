defmodule PauseAiCa.Volunteers.Signup do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "volunteer_signups" do
    field :email, :string
    field :notes, :string, default: ""
    belongs_to :user, PauseAiCa.Accounts.User
    belongs_to :batch, PauseAiCa.Volunteers.Batch
    belongs_to :group, PauseAiCa.Volunteers.Group
    has_many :invitations, PauseAiCa.Volunteers.Invitation
    timestamps(type: :utc_datetime)
  end
end
