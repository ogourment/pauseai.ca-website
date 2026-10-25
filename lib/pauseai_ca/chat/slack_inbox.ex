defmodule PauseAiCa.Chat.SlackInbox do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "chat_slack_inbox" do
    field :team_id, :string
    field :event_id, :string
    field :payload, :map, redact: true
    field :status, :string, default: "pending"
    field :processed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
