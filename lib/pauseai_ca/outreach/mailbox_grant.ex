defmodule PauseAiCa.Outreach.MailboxGrant do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "outreach_mailbox_grants" do
    field(:mailbox_ref, :string)
    field(:revision, :integer, default: 1)
    field(:granted_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    belongs_to(:user, PauseAiCa.Accounts.User)
    belongs_to(:granted_by, PauseAiCa.Accounts.User)
    belongs_to(:revoked_by, PauseAiCa.Accounts.User)
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule PauseAiCa.Outreach.MailboxGrantEvent do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "outreach_mailbox_grant_events" do
    field(:action, :string)
    field(:revision, :integer)
    belongs_to(:grant, PauseAiCa.Outreach.MailboxGrant)
    belongs_to(:actor, PauseAiCa.Accounts.User)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
