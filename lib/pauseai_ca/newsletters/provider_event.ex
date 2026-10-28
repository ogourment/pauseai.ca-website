defmodule PauseAiCa.Newsletters.ProviderEvent do
  @moduledoc "Immutable, minimal evidence matched to a frozen production delivery; no raw provider payload."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "newsletter_provider_events" do
    field :delivery_id, :binary_id
    field :event_key, :string
    field :email, :string, redact: true
    field :kind, :string
    field :reason, :string
    field :consent_conflict, :boolean, default: false
    field :occurred_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end
