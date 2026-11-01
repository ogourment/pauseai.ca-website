defmodule PauseAiCa.Repo.Migrations.AddOutreachConversations do
  use Ecto.Migration

  def up do
    PhoenixCRM.ConversationMigration.up()

    for table <- [:newsletter_drafts, :newsletter_batches] do
      alter table(table) do
        add(:outreach_mailbox_ref, :string)
        add(:outreach_email, :string)
        add(:conversation_id, references(:crm_conversations, type: :uuid, on_delete: :restrict))
        add(:reply_message_id, references(:crm_messages, type: :uuid, on_delete: :restrict))
      end
    end

    for {table, name} <- [
          {:newsletter_drafts, :newsletter_draft_mode},
          {:newsletter_batches, :newsletter_batch_mode}
        ] do
      drop(constraint(table, name))

      create(
        constraint(table, name,
          check: "recipient_mode IN ('contacts','newsletter','list','outreach')"
        )
      )
    end

    create table(:outreach_inbound_receipts, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:payload, :map, null: false)
      add(:payload_digest, :binary, null: false)
      add(:state, :string, null: false, default: "pending")
      add(:quarantined, {:array, :map}, null: false, default: [])
      add(:attempts, :integer, null: false, default: 0)
      add(:next_attempt_at, :utc_datetime_usec)
      add(:processed_at, :utc_datetime_usec)
      add(:files_pending, :boolean, null: false, default: false)
      add(:error, :text)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:outreach_inbound_receipts, [:payload_digest]))
    create(index(:outreach_inbound_receipts, [:state, :inserted_at]))

    create table(:outreach_reply_notifications, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:message_id, references(:crm_messages, type: :uuid, on_delete: :restrict), null: false)

      add(:conversation_id, references(:crm_conversations, type: :uuid, on_delete: :restrict),
        null: false
      )

      add(:mailbox_ref, :string, null: false)
      add(:recipient_actor_id, references(:users, type: :uuid, on_delete: :restrict))
      add(:state, :string, null: false, default: "pending")
      add(:attempted_at, :utc_datetime_usec)
      add(:accepted_at, :utc_datetime_usec)
      add(:error, :text)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:outreach_reply_notifications, [:message_id]))
    create(index(:outreach_reply_notifications, [:state, :inserted_at]))

    create(
      constraint(:outreach_reply_notifications, :outreach_notification_state,
        check: "state IN ('pending','reserved','accepted','unknown','unassigned','blocked')"
      )
    )
  end

  def down do
    # Refuse destructive downgrades until authored messages/receipts are explicitly reconciled.
    execute("""
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM crm_messages) OR EXISTS (SELECT 1 FROM outreach_inbound_receipts) THEN
        RAISE EXCEPTION 'Reconcile authored outreach messages/receipts before downgrade';
      END IF;
    END $$;
    """)

    for {table, name} <- [
          {:newsletter_drafts, :newsletter_draft_mode},
          {:newsletter_batches, :newsletter_batch_mode}
        ] do
      drop(constraint(table, name))
      create(constraint(table, name, check: "recipient_mode IN ('contacts','newsletter','list')"))
    end

    drop(table(:outreach_reply_notifications))
    drop(table(:outreach_inbound_receipts))

    for table <- [:newsletter_batches, :newsletter_drafts] do
      alter table(table) do
        remove(:reply_message_id)
        remove(:conversation_id)
        remove(:outreach_email)
        remove(:outreach_mailbox_ref)
      end
    end

    PhoenixCRM.ConversationMigration.down()
  end
end
