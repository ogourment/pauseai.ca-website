defmodule PauseAiCa.Repo.Migrations.AddCampaignSendIntents do
  use Ecto.Migration

  def change do
    create table(:campaign_send_intents, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :fingerprint, :binary, null: false
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action_id, references(:actions, type: :binary_id, on_delete: :nilify_all)
      add :kind, :text, null: false
      add :state, :text, null: false
      add :provider_id, :text
      add :error_code, :text
      add :template_id, :uuid
      add :template_revision, :integer
      add :attempted_at, :utc_datetime_usec
      add :accepted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:campaign_send_intents, [:fingerprint])
    create unique_index(:campaign_send_intents, [:action_id])
    create index(:campaign_send_intents, [:actor_id, :inserted_at])

    create constraint(:campaign_send_intents, :campaign_send_intent_kind,
             check: "kind IN ('assisted', 'handoff')"
           )

    create constraint(:campaign_send_intents, :campaign_send_intent_state,
             check:
               "state IN ('ready', 'awaiting_confirmation', 'submitting', 'accepted', 'rejected', 'unknown', 'handoff')"
           )

    create constraint(:campaign_send_intents, :campaign_send_intent_fingerprint,
             check: "octet_length(fingerprint) = 32"
           )

    create constraint(:campaign_send_intents, :campaign_send_intent_template,
             check:
               "(template_id IS NULL AND template_revision IS NULL) OR (template_id IS NOT NULL AND template_revision > 0)"
           )

    alter table(:pending_letters) do
      add :send_intent_id,
          references(:campaign_send_intents, type: :binary_id, on_delete: :nilify_all)
    end

    create unique_index(:pending_letters, [:send_intent_id])
  end
end
