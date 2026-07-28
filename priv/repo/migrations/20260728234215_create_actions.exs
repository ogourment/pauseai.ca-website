defmodule PauseAiCa.Repo.Migrations.CreateActions do
  use Ecto.Migration

  def change do
    create table(:actions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action_type, :string, null: false
      add :happened_on, :date, null: false
      add :notes, :text
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:actions, [:user_id])
  end
end
