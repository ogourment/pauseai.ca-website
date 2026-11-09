defmodule PauseAiCa.Campaigns.SendIntent do
  @moduledoc "Durable reviewed-letter identity and acceptance metadata. Letter bodies and addresses are not stored here."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "campaign_send_intents" do
    field :fingerprint, :binary, redact: true
    field :actor_id, :binary_id
    field :action_id, :binary_id
    field :kind, :string
    field :state, :string
    field :provider_id, :string, redact: true
    field :error_code, :string
    field :template_id, :binary_id
    field :template_revision, :integer
    field :attempted_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
