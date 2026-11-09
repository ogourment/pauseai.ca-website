defmodule PauseAiCa.Repo.Migrations.AddPublicGroupStageAndNextEvent do
  use Ecto.Migration

  def change do
    alter table(:incubator_profiles) do
      add :stage, :string, null: false, default: "active"
      add :next_event_title_en, :string
      add :next_event_title_fr, :string
      add :next_event_starts_at, :utc_datetime
      add :next_event_timezone, :string
      add :next_event_url, :string
    end

    create constraint(:incubator_profiles, :incubator_profiles_stage,
             check: "stage IN ('active', 'incubator')"
           )
  end
end
