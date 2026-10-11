defmodule PauseAiCa.Repo.Migrations.AddDynamicMailingLists do
  use Ecto.Migration

  def up do
    PhoenixCRM.MailingListsMigration.up()

    alter table(:newsletter_drafts) do
      add :mailing_list_id, references(:crm_mailing_lists, type: :uuid, on_delete: :restrict)
    end

    alter table(:newsletter_batches) do
      add :mailing_list_id, references(:crm_mailing_lists, type: :uuid, on_delete: :restrict)
      add :mailing_list_revision, :integer
    end

    for {table, name} <- [
          {:newsletter_drafts, :newsletter_draft_mode},
          {:newsletter_batches, :newsletter_batch_mode}
        ] do
      drop constraint(table, name)
      create constraint(table, name, check: "recipient_mode IN ('contacts','newsletter','list')")
    end
  end

  def down do
    # Existing list-mode records must be explicitly reconciled before a runtime downgrade.
    for {table, name} <- [
          {:newsletter_drafts, :newsletter_draft_mode},
          {:newsletter_batches, :newsletter_batch_mode}
        ] do
      drop constraint(table, name)
      create constraint(table, name, check: "recipient_mode IN ('contacts','newsletter')")
    end

    alter table(:newsletter_batches) do
      remove :mailing_list_revision
      remove :mailing_list_id
    end

    alter table(:newsletter_drafts) do
      remove :mailing_list_id
    end

    PhoenixCRM.MailingListsMigration.down()
  end
end
