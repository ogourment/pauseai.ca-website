defmodule PauseAiCa.Repo.Migrations.AddPersonalProfileContact do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :profile_contact, :map
    end
  end
end
