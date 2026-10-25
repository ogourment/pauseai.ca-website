defmodule PauseAiCa.Repo.Migrations.AddWelcomeCohorts do
  use Ecto.Migration

  def change do
    create table(:welcome_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:volunteer_groups, type: :binary_id, on_delete: :restrict),
        null: false

      add :host_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :title, :string, null: false
      add :language, :string, null: false
      add :timezone, :string, null: false
      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec, null: false
      add :meeting_url, :text, null: false
      add :status, :string, null: false, default: "scheduled"
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:welcome_sessions, [:id, :group_id])
    create index(:welcome_sessions, [:group_id, :starts_at])

    create constraint(:welcome_sessions, :welcome_sessions_positive_duration,
             check: "ends_at > starts_at"
           )

    create table(:welcome_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, :binary_id, null: false

      add :session_id,
          references(:welcome_sessions,
            type: :binary_id,
            with: [group_id: :group_id],
            on_delete: :restrict
          ), null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :draft_batch_id, references(:mail_batches, type: :binary_id, on_delete: :restrict)
      add :invitation_state, :string, null: false, default: "selected"
      add :invited_at, :utc_datetime_usec
      add :rsvp, :string, null: false, default: "pending"
      add :responded_at, :utc_datetime_usec
      add :attendance, :string, null: false, default: "unknown"
      add :attendance_by_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :follow_up, :string, null: false, default: "pending"
      add :notes, :text, null: false, default: ""
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:welcome_participants, [:session_id, :user_id])
    create index(:welcome_participants, [:user_id])

    create table(:welcome_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:volunteer_groups, type: :binary_id, on_delete: :restrict),
        null: false

      add :session_id, references(:welcome_sessions, type: :binary_id, on_delete: :restrict),
        null: false

      add :participant_id,
          references(:welcome_participants, type: :binary_id, on_delete: :restrict)

      add :actor_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :action, :string, null: false
      add :command_id, :string, null: false
      add :fingerprint, :binary, null: false
      add :result_kind, :string, null: false
      add :result_id, :binary_id, null: false
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:welcome_events, [:group_id, :actor_id, :command_id])
  end
end
