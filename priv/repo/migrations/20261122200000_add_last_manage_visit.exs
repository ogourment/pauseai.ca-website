defmodule PauseAiCa.Repo.Migrations.AddLastManageVisit do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_manage_visit_at, :utc_datetime_usec
    end
  end
end
