defmodule PauseAiCa.Repo.Migrations.CreateNewsletterDrafts do
  use Ecto.Migration

  def change do
    create table(:newsletter_drafts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :subject, :text, null: false, default: ""
      add :source, :text, null: false, default: ""
      add :region, :text, null: false, default: ""
      add :revision, :integer, null: false, default: 1
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:newsletter_drafts, [:owner_id, :archived_at])
    create constraint(:newsletter_drafts, :newsletter_draft_revision, check: "revision > 0")
  end
end
