defmodule PauseAiCa.Repo.Migrations.CreateLearningSignals do
  use Ecto.Migration

  def change do
    create table(:learning_signals) do
      add :visitor_id, :uuid, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :subject, :string, null: false, default: ""
      add :value, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:learning_signals, [:visitor_id, :kind, :subject])
    create index(:learning_signals, [:user_id])
    create index(:learning_signals, [:kind])
  end
end
