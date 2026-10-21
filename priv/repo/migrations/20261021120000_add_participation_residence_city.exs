defmodule PauseAiCa.Repo.Migrations.AddParticipationResidenceCity do
  use Ecto.Migration

  def change do
    alter table(:participation_requests) do
      add :residence_city, :string
    end
  end
end
