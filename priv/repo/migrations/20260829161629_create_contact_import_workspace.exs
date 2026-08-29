defmodule PauseAiCa.Repo.Migrations.CreateContactImportWorkspace do
  use Ecto.Migration

  def change do
    create table(:contact_imports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :filename, :string, null: false
      add :source, :string, null: false
      add :selected_count, :integer, null: false, default: 0
      add :imported_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create table(:contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :name, :string
      add :city, :string
      add :source, :string, null: false
      add :source_key, :string
      add :source_data, :map, null: false, default: %{}
      add :classification, :string, null: false, default: "needs_review"
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :last_import_id, references(:contact_imports, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:contacts, [:email])
    create index(:contacts, [:classification])
    create index(:contacts, [:user_id])

    create table(:contact_activities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :contact_id, references(:contacts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :actor_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:contact_activities, [:contact_id, :inserted_at])
  end
end
