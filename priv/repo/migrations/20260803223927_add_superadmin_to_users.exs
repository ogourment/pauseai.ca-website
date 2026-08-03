defmodule PauseAiCa.Repo.Migrations.AddSuperadminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :superadmin, :boolean, null: false, default: false
    end
  end
end
