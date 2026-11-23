defmodule PauseAiCa.Repo.Migrations.AddChapterPages do
  use Ecto.Migration

  def change do
    create table(:chapter_pages) do
      add :group_id, references(:volunteer_groups, type: :binary_id), null: false
      add :slug, :text, null: false
      add :revision, :integer, null: false, default: 1
      add :draft, :map, null: false
      add :published, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chapter_pages, [:group_id, :slug])

    create table(:chapter_page_edits) do
      add :page_id, references(:chapter_pages), null: false
      add :actor_id, references(:users, type: :binary_id), null: false
      add :revision, :integer, null: false
      add :action, :text, null: false
      add :content, :map, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:chapter_page_edits, [:page_id, :revision])
  end
end
