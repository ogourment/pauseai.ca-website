defmodule PauseAiCa.Repo.Migrations.AddAssistantAnchorCheckpoint do
  use Ecto.Migration
  def up, do: PhoenixAgentAssistant.AnchorClientMigration.up()
  def down, do: PhoenixAgentAssistant.AnchorClientMigration.down()
end
