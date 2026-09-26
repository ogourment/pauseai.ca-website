defmodule PauseAiCa.Repo.Migrations.PreserveVolunteerCsvMapping do
  use Ecto.Migration

  def up do
    alter table(:volunteer_batches) do
      add :csv_mapping, :map, null: false, default: %{}
    end
  end

  def down do
    execute "ALTER TABLE volunteer_batches DROP COLUMN IF EXISTS csv_mapping"
  end
end
