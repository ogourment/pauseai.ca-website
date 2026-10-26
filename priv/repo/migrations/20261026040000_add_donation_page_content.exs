defmodule PauseAiCa.Repo.Migrations.AddDonationPageContent do
  use Ecto.Migration

  def change do
    create table(:donation_pages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :text, null: false, default: "main"
      add :payload, :map, null: false, default: %{}
      add :published_payload, :map
      add :published_revision, :integer
      add :published_at, :utc_datetime_usec
      add :revision, :integer, null: false, default: 0
      add :updated_by, references(:users, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:donation_pages, [:key])
    create constraint(:donation_pages, :donation_pages_main_only, check: "key = 'main'")

    create constraint(:donation_pages, :donation_pages_revision_nonnegative,
             check: "revision >= 0"
           )

    create table(:donation_page_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :page_id, references(:donation_pages, type: :binary_id), null: false
      add :revision, :integer, null: false
      add :editor_id, references(:users, type: :binary_id), null: false
      add :action, :text, null: false
      add :payload, :map, null: false
      add :published_payload, :map
      add :published_revision, :integer
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:donation_page_revisions, [:page_id, :revision])

    create constraint(:donation_page_revisions, :donation_page_revisions_action,
             check: "action IN ('created', 'saved', 'published', 'restored')"
           )
  end
end
