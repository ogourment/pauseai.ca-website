defmodule PauseAiCa.Repo.Migrations.AddAccountPhone do
  use Ecto.Migration

  def change do
    alter table(:users), do: add(:phone, :string)
    alter table(:participation_requests), do: add(:phone, :string)
  end
end
