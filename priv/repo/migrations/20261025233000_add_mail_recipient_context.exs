defmodule PauseAiCa.Repo.Migrations.AddMailRecipientContext do
  use Ecto.Migration

  def change do
    alter table(:mail_batches) do
      add :recipient_context, :map, null: false, default: %{}
    end
  end
end
