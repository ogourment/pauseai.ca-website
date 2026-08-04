defmodule PauseAiCa.Repo.Migrations.AddSavedResourcesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :saved_resources, {:array, :string}, null: false, default: []
    end
  end
end
