defmodule PauseAiCa.Newsletters.Delivery do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "newsletter_deliveries" do
    field :batch_id, :binary_id
    field :authorizing_admin_id, :binary_id
    field :recipient_key, :string
    field :email, :string, redact: true
    field :withdrawal_token, :string, redact: true
    field :state, :string, default: "pending"
    field :attempted_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :provider_id, :string
    field :error, :string
    timestamps(type: :utc_datetime_usec)
  end
end
