defmodule PauseAiCa.Repo.Migrations.AddNewsletterEditions do
  use Ecto.Migration

  def change do
    create table(:newsletter_language_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :text, null: false
      add :locale, :text, null: false
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:newsletter_language_preferences, [:email, :inserted_at])

    alter table(:newsletter_drafts) do
      add :edition, :text, null: false, default: "unknown"
    end

    alter table(:newsletter_batches) do
      add :edition, :text, null: false, default: "unknown"
    end
  end
end
