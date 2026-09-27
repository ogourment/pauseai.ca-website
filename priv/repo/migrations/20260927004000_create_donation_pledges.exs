defmodule PauseAiCa.Repo.Migrations.CreateDonationPledges do
  use Ecto.Migration

  def change do
    create table(:donation_pledges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :email, :string, null: false
      add :amount_cad, :decimal, precision: 12, scale: 2
      add :notes, :text, null: false, default: ""
      add :locale, :string, null: false
      add :consented_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:donation_pledges, [:email])
  end
end
