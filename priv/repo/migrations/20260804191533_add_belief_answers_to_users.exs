defmodule PauseAiCa.Repo.Migrations.AddBeliefAnswersToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :belief_answers, :map, null: false, default: %{}
    end
  end
end
