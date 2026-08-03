defmodule PauseAiCa.Repo.Migrations.AddDetailToActions do
  use Ecto.Migration

  def change do
    # An action people did off the platform is only worth recording if it can
    # carry what actually happened: where the meeting was, how many turned up,
    # how many flyers went out. Two typed columns rather than a JSON blob,
    # because "how many people did we reach this month" should be a sum.
    alter table(:actions) do
      add :location, :string
      add :quantity, :integer
    end
  end
end
