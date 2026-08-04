defmodule PauseAiCa.Repo.Migrations.AddProfileContextToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :postal_code, :string
      add :representative, :map
      add :custom_resource_urls, {:array, :string}, null: false, default: []
    end
  end
end
