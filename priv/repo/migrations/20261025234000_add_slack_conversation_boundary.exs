defmodule PauseAiCa.Repo.Migrations.AddSlackConversationBoundary do
  use Ecto.Migration

  def change do
    create table(:chat_slack_oauth_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :state_hash, :binary, null: false
      add :session_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:chat_slack_oauth_states, [:state_hash])

    create table(:chat_slack_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :team_id, :string, null: false
      add :provider_user_id, :string, null: false
      add :token_cipher, :text
      add :refresh_cipher, :text
      add :expires_at, :utc_datetime_usec
      add :scopes, {:array, :string}, null: false, default: []
      add :active, :boolean, null: false, default: true
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:chat_slack_links, [:team_id, :provider_user_id])

    create unique_index(:chat_slack_links, [:team_id, :user_id],
             where: "active = true",
             name: :chat_slack_one_active_link
           )

    create table(:chat_slack_inbox, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :team_id, :string, null: false
      add :event_id, :string, null: false
      add :payload, :map, null: false
      add :status, :string, null: false, default: "pending"
      add :processed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:chat_slack_inbox, [:team_id, :event_id])
    create index(:chat_slack_inbox, [:team_id, :status, :inserted_at])

    create table(:chat_slack_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :team_id, :string, null: false
      add :channel_id, :string, null: false
      add :external_ts, :string, null: false
      add :version, :string, null: false
      add :text, :text
      add :provider_user_id, :string
      add :bot_id, :string
      add :thread_ts, :string
      add :deleted, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:chat_slack_messages, [:team_id, :channel_id, :external_ts])
    create index(:chat_slack_messages, [:team_id, :channel_id, :deleted])

    create table(:chat_slack_outbox, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :link_id, references(:chat_slack_links, type: :binary_id), null: false
      add :link_revision, :integer, null: false
      add :team_id, :string, null: false
      add :channel_id, :string, null: false
      add :thread_ts, :string
      add :text, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :external_ts, :string
      add :permalink, :text
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create index(:chat_slack_outbox, [:user_id, :status])

    create constraint(:chat_slack_outbox, :chat_slack_outbox_status,
             check:
               "status IN ('draft','pending','sending','sent','failed','uncertain','cancelled')"
           )
  end
end
