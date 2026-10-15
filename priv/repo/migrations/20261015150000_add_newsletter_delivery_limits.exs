defmodule PauseAiCa.Repo.Migrations.AddNewsletterDeliveryLimits do
  use Ecto.Migration

  def change do
    create table(:newsletter_delivery_limits) do
      add :personal, :integer, null: false
      add :global, :integer, null: false
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:newsletter_delivery_limits, :valid_delivery_limits,
             check: "personal > 0 AND personal <= global AND global <= 100000"
           )
  end
end
