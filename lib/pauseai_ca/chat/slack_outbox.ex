defmodule PauseAiCa.Chat.SlackOutbox do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "chat_slack_outbox" do
    field :user_id, :binary_id
    field :link_id, :binary_id
    field :link_revision, :integer
    field :team_id, :string
    field :channel_id, :string
    field :thread_ts, :string
    field :text, :string, redact: true
    field :status, :string, default: "draft"
    field :external_ts, :string
    field :permalink, :string
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
