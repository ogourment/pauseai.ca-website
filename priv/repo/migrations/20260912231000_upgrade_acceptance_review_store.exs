defmodule PauseAiCa.Repo.Migrations.UpgradeAcceptanceReviewStore do
  use Ecto.Migration

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS acceptance_archive")

    for table <- ["acceptance_harness_comments", "acceptance_harness_statuses"] do
      execute("""
      DO $$ BEGIN
        IF to_regclass('public.#{table}') IS NOT NULL THEN
          ALTER TABLE public.#{table} SET SCHEMA acceptance_archive;
        END IF;
      END $$;
      """)
    end

    flush()
    AcceptanceHarness.AdminStore.install!(repo: repo())
  end

  def down, do: raise("Acceptance store upgrade is forward-only; restore the pre-upgrade backup")
end
