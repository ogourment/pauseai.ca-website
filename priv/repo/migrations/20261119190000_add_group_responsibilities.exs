defmodule PauseAiCa.Repo.Migrations.AddGroupResponsibilities do
  use Ecto.Migration

  def change do
    create table(:group_responsibilities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :membership_id,
          references(:incubator_memberships, type: :binary_id, on_delete: :restrict), null: false

      add :title, :string, null: false
      add :starts_on, :date, null: false
      add :ends_on, :date
      add :revision, :integer, default: 1, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:group_responsibilities, [:membership_id])
  end
end
