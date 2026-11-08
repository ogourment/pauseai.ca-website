defmodule PauseAiCa.Repo.Migrations.AddAssistantSpendLedger do
  use Ecto.Migration
  def up, do: PhoenixAgentAssistant.SpendLedgerMigration.up()
  def down, do: PhoenixAgentAssistant.SpendLedgerMigration.down()
end
