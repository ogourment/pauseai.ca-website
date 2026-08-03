defmodule PauseAiCa.Repo.Migrations.AddConfirmationToActions do
  use Ecto.Migration

  def change do
    # A letter opened in someone's own mail client may or may not have been
    # sent; only they know. Such an action starts unconfirmed and the dashboard
    # asks. Actions we performed ourselves are confirmed on creation.
    alter table(:actions) do
      add :confirmed_at, :utc_datetime
    end

    create index(:actions, [:user_id, :confirmed_at])

    # Everything recorded before this migration was user-entered, so confirmed.
    execute "UPDATE actions SET confirmed_at = inserted_at WHERE confirmed_at IS NULL",
            "SELECT 1"
  end
end
