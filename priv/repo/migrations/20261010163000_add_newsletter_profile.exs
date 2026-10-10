defmodule PauseAiCa.Repo.Migrations.AddNewsletterProfile do
  use Ecto.Migration

  def change do
    alter table(:newsletter_subscriptions) do
      add :name, :text
      add :fsa, :string, size: 3
    end
  end
end
