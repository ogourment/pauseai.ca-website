defmodule PauseAiCa.Repo.Migrations.CreatePendingLetters do
  use Ecto.Migration

  def change do
    # A letter waiting for its sender to prove they own the address it will
    # reply to. Rows are deleted as soon as the letter is sent, and swept when
    # they expire, so this is a queue and not a store of supporter data.
    create table(:pending_letters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :binary, null: false
      add :sender_name, :string
      add :sender_email, :string, null: false
      add :recipients, :string, null: false
      add :subject, :string, null: false
      add :body, :text, null: false
      add :locale, :string, null: false, default: "en"
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:pending_letters, [:token])
    create index(:pending_letters, [:expires_at])
  end
end
