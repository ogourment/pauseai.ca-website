defmodule PauseAiCa.Repo.Migrations.AddMailDeliveryReceipts do
  use Ecto.Migration

  def change do
    create table(:mail_delivery_receipts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_id, :uuid
      add :newsletter_delivery_id, :uuid
      add :recipients, {:array, :text}, null: false
      add :subject, :text, null: false
      add :sender_email, :text, null: false
      add :state, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:mail_delivery_receipts, [:recipients], using: :gin)
  end
end
