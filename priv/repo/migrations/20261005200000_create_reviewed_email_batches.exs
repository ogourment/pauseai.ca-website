defmodule PauseAiCa.Repo.Migrations.CreateReviewedEmailBatches do
  use Ecto.Migration

  def change do
    alter table(:newsletter_drafts) do
      add :recipient_mode, :text, null: false, default: "newsletter"
      add :recipient_keys, {:array, :text}, null: false, default: []
    end

    create constraint(:newsletter_drafts, :newsletter_draft_mode,
             check: "recipient_mode IN ('contacts','newsletter')"
           )

    create table(:newsletter_batches, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :draft_id, references(:newsletter_drafts, type: :uuid, on_delete: :restrict),
        null: false

      add :owner_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :approver_id, references(:users, type: :uuid, on_delete: :restrict)
      add :draft_revision, :integer, null: false
      add :recipient_mode, :text, null: false
      add :recipient_keys, {:array, :text}, null: false
      add :state, :text, null: false, default: "review"
      add :sender_name, :text, null: false
      add :sender_email, :text, null: false
      add :delivery_environment, :text, null: false
      add :subject, :text, null: false
      add :source, :text, null: false
      add :preparation_key, :binary, null: false
      add :audience_digest, :binary, null: false
      add :reviewed_at, :utc_datetime_usec, null: false
      add :approved_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:newsletter_batches, [:owner_id, :inserted_at])
    create unique_index(:newsletter_batches, [:preparation_key])

    create constraint(:newsletter_batches, :newsletter_batch_state,
             check: "state IN ('review','approved','sending','completed','stale','paused')"
           )

    create constraint(:newsletter_batches, :newsletter_batch_mode,
             check: "recipient_mode IN ('contacts','newsletter')"
           )

    create table(:newsletter_deliveries, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :batch_id, references(:newsletter_batches, type: :uuid, on_delete: :restrict),
        null: false

      add :authorizing_admin_id, references(:users, type: :uuid, on_delete: :restrict)
      add :recipient_key, :text, null: false
      add :email, :text, null: false
      add :withdrawal_token, :text, null: false
      add :state, :text, null: false, default: "pending"
      add :attempted_at, :utc_datetime_usec
      add :accepted_at, :utc_datetime_usec
      add :provider_id, :text
      add :error, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:newsletter_deliveries, [:batch_id, :email])
    create index(:newsletter_deliveries, [:attempted_at])

    create constraint(:newsletter_deliveries, :newsletter_delivery_actor,
             check: "attempted_at IS NULL OR authorizing_admin_id IS NOT NULL"
           )

    create constraint(:newsletter_deliveries, :newsletter_delivery_state,
             check: "state IN ('pending','reserved','accepted','unknown','failed','excluded')"
           )

    execute(
      "ALTER TABLE newsletter_subscriptions DROP CONSTRAINT newsletter_state",
      "ALTER TABLE newsletter_subscriptions ADD CONSTRAINT newsletter_state CHECK (state IN ('pending','confirmed','withdrawn','legacy_review'))"
    )

    execute(
      "ALTER TABLE newsletter_subscriptions ADD CONSTRAINT newsletter_state CHECK (state IN ('pending','confirmed','withdrawn','legacy_review','outreach_only'))",
      "ALTER TABLE newsletter_subscriptions DROP CONSTRAINT newsletter_state"
    )
  end
end
