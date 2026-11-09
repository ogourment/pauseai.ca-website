defmodule PauseAiCa.Repo.Migrations.AddAssistantInstructions do
  use Ecto.Migration

  def change do
    create table(:assistant_instructions, primary_key: false) do
      add :id, :integer, primary_key: true
      add :source, :text, null: false
      add :published_source, :text
      add :revision, :integer, null: false, default: 0
      add :published_revision, :integer
      add :updated_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :published_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :published_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:assistant_instructions, :assistant_instructions_singleton, check: "id = 1")

    create table(:assistant_instruction_revisions) do
      add :revision, :integer, null: false
      add :editor_id, :binary_id, null: false
      add :action, :string, null: false
      add :source, :text, null: false
      add :published_source, :text
      add :published_revision, :integer
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:assistant_instruction_revisions, [:revision])
  end
end
