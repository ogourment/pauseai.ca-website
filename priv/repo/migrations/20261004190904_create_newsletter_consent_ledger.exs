defmodule PauseAiCa.Repo.Migrations.CreateNewsletterConsentLedger do
  use Ecto.Migration

  def change do
    create table(:newsletter_subscriptions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :text, null: false
      add :state, :text, null: false
      add :locale, :text, null: false, default: "en"
      add :city, :text
      add :region, :text
      add :consent_version, :text
      add :requested_at, :utc_datetime_usec
      add :confirmed_at, :utc_datetime_usec
      add :withdrawn_at, :utc_datetime_usec
      add :confirmation_hash, :binary
      add :confirmation_expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:newsletter_subscriptions, [:email])
    create unique_index(:newsletter_subscriptions, [:confirmation_hash])

    create constraint(:newsletter_subscriptions, :newsletter_state,
             check: "state IN ('pending', 'confirmed', 'withdrawn', 'legacy_review')"
           )

    create constraint(:newsletter_subscriptions, :newsletter_confirmation_evidence,
             check:
               "state <> 'confirmed' OR (confirmed_at IS NOT NULL AND consent_version IS NOT NULL)"
           )

    create constraint(:newsletter_subscriptions, :newsletter_withdrawal_evidence,
             check: "state <> 'withdrawn' OR withdrawn_at IS NOT NULL"
           )

    create table(:newsletter_withdrawal_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :subscription_id,
          references(:newsletter_subscriptions, type: :uuid, on_delete: :delete_all), null: false

      add :token_hash, :binary, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:newsletter_withdrawal_tokens, [:token_hash])
    create index(:newsletter_withdrawal_tokens, [:subscription_id])

    create table(:newsletter_consent_events, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :subscription_id,
          references(:newsletter_subscriptions, type: :uuid, on_delete: :restrict), null: false

      add :kind, :text, null: false
      add :consent_version, :text
      add :actor_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :evidence, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:newsletter_consent_events, [:subscription_id, :inserted_at])
  end
end
