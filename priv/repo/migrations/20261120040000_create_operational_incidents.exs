defmodule PauseAiCa.Repo.Migrations.CreateOperationalIncidents do
  use Ecto.Migration

  def change do
    create table(:operational_incidents) do
      add :environment, :text, null: false
      add :source, :text, null: false
      add :category, :text, null: false
      add :location, :text, null: false
      add :release, :text, null: false
      add :request_ref, :uuid
      add :occurrences, :bigint, null: false
      add :last_seen, :utc_datetime, null: false
      add :attempts, :integer, default: 0, null: false
      add :next_attempt, :utc_datetime, null: false
      add :sent, :boolean, default: false, null: false
    end

    create unique_index(:operational_incidents, [:environment, :source, :category, :location])

    create table(:operational_alert_attempts) do
      add :environment, :text, null: false
      add :attempted_at, :utc_datetime, null: false
    end

    create index(:operational_alert_attempts, [:environment, :attempted_at])
  end
end
