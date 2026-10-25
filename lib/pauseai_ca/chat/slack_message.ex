defmodule PauseAiCa.Chat.SlackMessage do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "chat_slack_messages" do
    field :team_id, :string
    field :channel_id, :string
    field :external_ts, :string
    field :version, :string
    field :text, :string, redact: true
    field :provider_user_id, :string
    field :bot_id, :string
    field :thread_ts, :string
    field :deleted, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end
end
