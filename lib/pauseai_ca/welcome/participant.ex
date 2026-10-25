defmodule PauseAiCa.Welcome.Participant do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "welcome_participants" do
    belongs_to :group, PauseAiCa.Volunteers.Group
    belongs_to :session, PauseAiCa.Welcome.Session
    belongs_to :user, PauseAiCa.Accounts.User
    belongs_to :draft_batch, PauseAiCa.Mail.Batch
    field :invitation_state, :string, default: "selected"
    field :invited_at, :utc_datetime_usec
    field :rsvp, :string, default: "pending"
    field :responded_at, :utc_datetime_usec
    field :attendance, :string, default: "unknown"
    field :attendance_by_id, :binary_id
    field :follow_up, :string, default: "pending"
    field :notes, :string, default: "", redact: true
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
