defmodule PauseAiCa.Repo.Migrations.AddNewsletterResultSnapshots do
  use Ecto.Migration

  def change do
    create table(:newsletter_result_snapshots, primary_key: false) do
      add :batch_id, references(:newsletter_batches, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :observed, :map, null: false
      add :partial, :boolean, null: false, default: false
      add :refreshed_at, :utc_datetime_usec, null: false
    end
  end
end
