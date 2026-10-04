defmodule PauseAiCa.Repo.Migrations.CreateLearningGameAttempts do
  use Ecto.Migration

  def change do
    create table(:learning_game_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :visitor_id, :uuid, null: false
      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :locale, :string, null: false
      add :sequence, :integer, null: false, default: 0
      add :furthest_stage, :integer, null: false, default: 0
      add :completed, :boolean, null: false, default: false
      add :buttons, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:learning_game_attempts, [:visitor_id])
    create index(:learning_game_attempts, [:user_id])
  end
end
