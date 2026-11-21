defmodule PauseAiCa.Repo.Migrations.AllowConfiguredOutreachMailboxes do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE outreach_mailbox_grants DROP CONSTRAINT outreach_mailbox_ref, ADD CONSTRAINT outreach_mailbox_ref CHECK (mailbox_ref ~ '^[a-z][a-z0-9_]{0,63}$')",
      "ALTER TABLE outreach_mailbox_grants DROP CONSTRAINT outreach_mailbox_ref, ADD CONSTRAINT outreach_mailbox_ref CHECK (mailbox_ref IN ('outreach_en', 'outreach_fr'))"
    )
  end
end
