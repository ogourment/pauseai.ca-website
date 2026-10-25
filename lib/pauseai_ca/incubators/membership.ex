defmodule PauseAiCa.Incubators.Membership do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "incubator_memberships" do
    field :group_id, :binary_id
    field :user_id, :binary_id
    field :display_name, :string
    field :identifier, :string, redact: true
    field :status, :string, default: "pending"
    field :role, :string, default: "member"
    field :conduct_at, :utc_datetime_usec
    field :matched_at, :utc_datetime_usec
    field :matched_by_id, :binary_id
    field :code_hash, :binary, redact: true
    field :code_issued_at, :utc_datetime_usec
    field :code_expires_at, :utc_datetime_usec
    field :code_attempts, :integer, default: 0
    field :external_removal_pending, :boolean, default: false
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
