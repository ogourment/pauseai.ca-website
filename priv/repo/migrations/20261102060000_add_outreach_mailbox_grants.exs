defmodule PauseAiCa.Repo.Migrations.AddOutreachMailboxGrants do
  use Ecto.Migration

  def change do
    alter table(:newsletter_batches) do
      add(:outreach_access_fingerprint, :text)
    end

    create table(:outreach_mailbox_grants, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:mailbox_ref, :text, null: false)
      add(:user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false)
      add(:granted_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false)
      add(:revoked_by_id, references(:users, type: :binary_id, on_delete: :restrict))
      add(:revision, :integer, null: false, default: 1)
      add(:granted_at, :utc_datetime_usec, null: false)
      add(:revoked_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:outreach_mailbox_grants, [:mailbox_ref, :user_id]))
    create(index(:outreach_mailbox_grants, [:user_id]))

    create(
      constraint(:outreach_mailbox_grants, :outreach_mailbox_ref,
        check: "mailbox_ref IN ('outreach_en','outreach_fr')"
      )
    )

    create(constraint(:outreach_mailbox_grants, :outreach_grant_revision, check: "revision > 0"))

    create table(:outreach_mailbox_grant_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:grant_id, references(:outreach_mailbox_grants, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:actor_id, references(:users, type: :binary_id, on_delete: :restrict), null: false)
      add(:action, :text, null: false)
      add(:revision, :integer, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:outreach_mailbox_grant_events, [:grant_id, :revision]))

    create(
      constraint(:outreach_mailbox_grant_events, :outreach_grant_action,
        check: "action IN ('granted','revoked') AND revision > 0"
      )
    )
  end
end
