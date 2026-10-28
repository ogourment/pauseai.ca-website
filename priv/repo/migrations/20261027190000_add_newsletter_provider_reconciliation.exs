defmodule PauseAiCa.Repo.Migrations.AddNewsletterProviderReconciliation do
  use Ecto.Migration

  def change do
    create table(:newsletter_provider_events, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :delivery_id, references(:newsletter_deliveries, type: :uuid, on_delete: :restrict),
        null: false

      add :event_key, :string, null: false
      add :email, :string, null: false
      add :kind, :string, null: false
      add :reason, :string, null: false
      add :consent_conflict, :boolean, null: false, default: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:newsletter_provider_events, [:event_key])
    create index(:newsletter_provider_events, [:email, :kind, :reason])
    create index(:newsletter_provider_events, [:delivery_id])
    create index(:newsletter_deliveries, [:provider_id, :email])

    create constraint(:newsletter_provider_events, :newsletter_provider_event_kind,
             check: "kind IN ('hard_bounce', 'unsubscribe', 'review')"
           )

    create table(:newsletter_provider_sync_states, primary_key: false) do
      add :id, :string, primary_key: true
      add :cursor_at, :utc_datetime_usec
      add :last_full_scan_at, :utc_datetime_usec
      add :full_scan, :boolean, null: false, default: false
      add :window_start, :date
      add :window_end, :date
      add :offset, :integer, null: false, default: 0
      add :partial, :boolean, null: false, default: false
      add :last_attempt_at, :utc_datetime_usec
      add :last_success_at, :utc_datetime_usec
      add :last_error, :string
      add :counts, :map, null: false, default: %{}
    end
  end
end
