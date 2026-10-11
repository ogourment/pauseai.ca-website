defmodule PauseAiCa.Newsletters.Batch do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "newsletter_batches" do
    field :draft_id, :binary_id
    field :owner_id, :binary_id
    field :approver_id, :binary_id
    field :draft_revision, :integer
    field :mailing_list_id, :binary_id
    field :mailing_list_revision, :integer
    field :recipient_mode, :string
    field :recipient_keys, {:array, :string}
    field :state, :string, default: "review"
    field :sender_name, :string
    field :sender_email, :string
    field :delivery_environment, :string
    field :subject, :string
    field :source, :string, redact: true
    field :preparation_key, :binary
    field :audience_digest, :binary
    field :reviewed_at, :utc_datetime_usec
    field :approved_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
