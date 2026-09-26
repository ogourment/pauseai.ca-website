defmodule PauseAiCa.Repo.Migrations.CreateVolunteerSignups do
  use Ecto.Migration

  def change do
    create table(:volunteer_groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:volunteer_groups, ["lower(name)"])

    create table(:volunteer_group_managers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:volunteer_groups, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:volunteer_group_managers, [:group_id, :user_id])

    create table(:volunteer_batches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :default_group_id,
          references(:volunteer_groups, type: :binary_id, on_delete: :nilify_all)

      add :source, :string, null: false, default: ""
      add :state, :string, null: false, default: "draft"
      add :step, :string, null: false, default: "rows"
      add :wizard_row, :string
      add :rows, {:array, :map}, null: false, default: []
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create index(:volunteer_batches, [:owner_id])

    create table(:volunteer_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :details, :map, null: false, default: %{}
      add :draft, :map, null: false, default: %{}
      add :step, :string, null: false, default: "contact"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:volunteer_profiles, [:user_id])

    create table(:volunteer_signups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :batch_id, references(:volunteer_batches, type: :binary_id, on_delete: :restrict),
        null: false

      add :group_id, references(:volunteer_groups, type: :binary_id, on_delete: :restrict)
      add :notes, :text, null: false, default: ""
      timestamps(type: :utc_datetime)
    end

    create unique_index(:volunteer_signups, [:email])
    create index(:volunteer_signups, [:group_id])

    create table(:volunteer_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :signup_id, references(:volunteer_signups, type: :binary_id, on_delete: :delete_all),
        null: false

      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "queued"
      add :provider_id, :string
      add :attempted_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:volunteer_invitations, [:signup_id])
    create index(:volunteer_invitations, [:status])

    create table(:volunteer_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :batch_id, references(:volunteer_batches, type: :binary_id, on_delete: :delete_all)
      add :signup_id, references(:volunteer_signups, type: :binary_id, on_delete: :delete_all)
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:volunteer_events, [:batch_id])
  end
end
