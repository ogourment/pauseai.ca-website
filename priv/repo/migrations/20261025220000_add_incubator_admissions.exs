defmodule PauseAiCa.Repo.Migrations.AddIncubatorAdmissions do
  use Ecto.Migration

  def change do
    create table(:incubator_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:volunteer_groups, type: :binary_id, on_delete: :restrict),
        null: false

      add :name_en, :string, null: false
      add :name_fr, :string, null: false
      add :summary_en, :text, null: false, default: ""
      add :summary_fr, :text, null: false, default: ""
      add :fsas, {:array, :string}, null: false, default: []
      add :published, :boolean, null: false, default: false
      add :events_url, :string
      add :moderator_contact, :string
      add :whatsapp_enabled, :boolean, null: false, default: false
      add :whatsapp_invite_url, :string
      add :whatsapp_approval_confirmed, :boolean, null: false, default: false
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:incubator_profiles, [:group_id])

    create table(:incubator_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:volunteer_groups, type: :binary_id, on_delete: :restrict),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :display_name, :string, null: false
      add :identifier, :string
      add :status, :string, null: false, default: "pending"
      add :role, :string, null: false, default: "member"
      add :conduct_at, :utc_datetime_usec, null: false
      add :matched_at, :utc_datetime_usec
      add :matched_by_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :code_hash, :binary
      add :code_issued_at, :utc_datetime_usec
      add :code_expires_at, :utc_datetime_usec
      add :code_attempts, :integer, null: false, default: 0
      add :external_removal_pending, :boolean, null: false, default: false
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:incubator_memberships, [:group_id, :user_id])
    create index(:incubator_memberships, [:group_id, :status])

    create table(:incubator_membership_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :group_id, references(:volunteer_groups, type: :binary_id, on_delete: :restrict),
        null: false

      add :membership_id,
          references(:incubator_memberships, type: :binary_id, on_delete: :restrict)

      add :actor_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :action, :string, null: false
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:incubator_membership_events, [:group_id, :inserted_at])
  end
end
