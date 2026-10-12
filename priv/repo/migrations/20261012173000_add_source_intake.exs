defmodule PauseAiCa.Repo.Migrations.AddSourceIntake do
  use Ecto.Migration

  def change do
    alter table(:contact_imports), do: add(:actor_service, :string)

    create table(:crm_intake_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source, :string, null: false
      add :event_id, :string, null: false
      add :digest, :string, null: false
      add :import_id, references(:contact_imports, type: :binary_id)
      add :imported_count, :integer, null: false
      add :suppressed_count, :integer, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:crm_intake_receipts, [:source, :event_id])

    create table(:crm_intake_suppressions, primary_key: false) do
      add :email_hash, :string, primary_key: true
      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
