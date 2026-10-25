defmodule PauseAiCa.Repo.Migrations.AddOrganizerTasks do
  use Ecto.Migration

  def change do
    create table(:organizer_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:volunteer_groups, type: :binary_id, on_delete: :restrict),
        null: false

      add :requester_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :accountable_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :assignee_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :backup_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :title, :string, size: 200, null: false
      add :description, :text, null: false, default: ""
      add :status, :string, null: false, default: "open"
      add :source, :string, null: false, default: "manual"
      add :due_date, :date
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organizer_tasks, [:id, :group_id])
    create index(:organizer_tasks, [:group_id, :inserted_at])
    create constraint(:organizer_tasks, :organizer_tasks_revision_positive, check: "revision > 0")

    create constraint(:organizer_tasks, :organizer_tasks_backup_distinct,
             check: "backup_id IS NULL OR assignee_id IS NULL OR backup_id <> assignee_id"
           )

    create table(:organizer_task_dependencies, primary_key: false) do
      add :group_id, :binary_id, null: false

      add :task_id,
          references(:organizer_tasks,
            type: :binary_id,
            with: [group_id: :group_id],
            on_delete: :delete_all
          ),
          primary_key: true

      add :prerequisite_id,
          references(:organizer_tasks,
            type: :binary_id,
            with: [group_id: :group_id],
            on_delete: :restrict
          ),
          primary_key: true
    end

    create constraint(:organizer_task_dependencies, :organizer_task_dependencies_not_self,
             check: "task_id <> prerequisite_id"
           )

    create table(:organizer_task_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, :binary_id, null: false

      add :task_id,
          references(:organizer_tasks,
            type: :binary_id,
            with: [group_id: :group_id],
            on_delete: :restrict
          ),
          null: false

      add :actor_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :command_id, :string, null: false
      add :fingerprint, :binary, null: false
      add :action, :string, null: false
      add :revision, :integer, null: false
      add :details, :map, null: false, default: %{}
      add :result, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:organizer_task_events, [:group_id, :actor_id, :command_id])
    create unique_index(:organizer_task_events, [:task_id, :revision])
    create index(:organizer_task_events, [:group_id, :inserted_at])
  end
end
