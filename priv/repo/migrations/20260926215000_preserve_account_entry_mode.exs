defmodule PauseAiCa.Repo.Migrations.PreserveAccountEntryMode do
  use Ecto.Migration

  def change do
    alter table(:volunteer_batches) do
      add :entry_mode, :string, null: false, default: "multiple"
    end
  end
end
