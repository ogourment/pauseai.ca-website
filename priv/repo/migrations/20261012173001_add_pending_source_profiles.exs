defmodule PauseAiCa.Repo.Migrations.AddPendingSourceProfiles do
  use Ecto.Migration

  def change do
    create table(:crm_pending_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source, :string, null: false
      add :external_key, :string, null: false
      add :digest, :string, null: false
      add :original, :map, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:crm_pending_sources, [:source, :external_key, :digest])
  end
end
