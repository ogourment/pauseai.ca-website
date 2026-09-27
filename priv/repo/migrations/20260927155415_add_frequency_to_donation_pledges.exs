defmodule PauseAiCa.Repo.Migrations.AddFrequencyToDonationPledges do
  use Ecto.Migration

  def change do
    alter table(:donation_pledges) do
      add :frequency, :string, null: false, default: "one_time"
    end

    create constraint(:donation_pledges, :donation_pledges_frequency_check,
             check: "frequency IN ('one_time', 'monthly')"
           )
  end
end
