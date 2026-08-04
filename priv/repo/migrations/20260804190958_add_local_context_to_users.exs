defmodule PauseAiCa.Repo.Migrations.AddLocalContextToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :fsa, :string
      add :local_updates, :boolean, null: false, default: false
    end
  end
end
