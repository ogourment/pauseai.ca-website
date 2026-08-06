defmodule PauseAiCa.Repo.Migrations.CreateDailyVisits do
  use Ecto.Migration

  def change do
    create table(:daily_visits, primary_key: false) do
      add :visited_on, :date, primary_key: true
      add :count, :bigint, null: false, default: 0
    end
  end
end
