defmodule PauseAiCa.Repo.Migrations.AddMPTemplates do
  use Ecto.Migration

  def change do
    create table(:mp_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :revision, :integer, null: false, default: 0
      add :published_revision, :integer
      add :published_at, :utc_datetime_usec
      add :updated_by, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:mp_templates, [:slug])

    create table(:mp_template_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :template_id, references(:mp_templates, type: :binary_id, on_delete: :restrict),
        null: false

      add :revision, :integer, null: false
      add :editor_id, :binary_id, null: false
      add :action, :string, null: false
      add :payload, :map, null: false
      add :author_permission, :boolean, null: false, default: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:mp_template_revisions, [:template_id, :revision])
  end
end
