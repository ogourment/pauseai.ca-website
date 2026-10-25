defmodule PauseAiCa.Chat.SlackState do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "chat_slack_oauth_states" do
    field :user_id, :binary_id
    field :state_hash, :binary, redact: true
    field :session_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
