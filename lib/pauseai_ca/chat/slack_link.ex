defmodule PauseAiCa.Chat.SlackLink do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "chat_slack_links" do
    field :user_id, :binary_id
    field :team_id, :string
    field :provider_user_id, :string
    field :token_cipher, :string, redact: true
    field :refresh_cipher, :string, redact: true
    field :expires_at, :utc_datetime_usec
    field :scopes, {:array, :string}, default: []
    field :active, :boolean, default: true
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
