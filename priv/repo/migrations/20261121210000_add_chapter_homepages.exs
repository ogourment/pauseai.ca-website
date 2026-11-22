defmodule PauseAiCa.Repo.Migrations.AddChapterHomepages do
  use Ecto.Migration

  def change do
    alter table(:incubator_profiles) do
      add :chapter_slug, :text
      add :chapter_draft, :map, null: false, default: %{}
      add :chapter_content, :map
    end

    create unique_index(:incubator_profiles, [:chapter_slug])

    create table(:chapter_edits) do
      add :group_id, references(:volunteer_groups, type: :binary_id), null: false
      add :actor_id, references(:users, type: :binary_id), null: false
      add :revision, :integer, null: false
      add :action, :text, null: false
      add :content, :map, null: false
    end

    create unique_index(:chapter_edits, [:group_id, :revision])
  end
end
