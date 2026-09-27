defmodule PauseAiCa.Repo.Migrations.LabelVisitReportingTimezone do
  use Ecto.Migration

  def up do
    alter table(:daily_visits) do
      add :reporting_timezone, :string, null: false, default: "UTC"
    end

    execute "ALTER TABLE daily_visits DROP CONSTRAINT daily_visits_pkey"
    execute "ALTER TABLE daily_visits ADD PRIMARY KEY (visited_on, reporting_timezone)"
  end

  def down do
    raise "Cannot merge UTC and Toronto daily aggregates without losing their reporting boundaries"
  end
end
