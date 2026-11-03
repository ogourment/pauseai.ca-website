defmodule PauseAiCa.Repo.Migrations.AddAgentAssistant do
  use Ecto.Migration
  def up, do: PhoenixAgentAssistant.Store.Migration.up()
  def down, do: PhoenixAgentAssistant.Store.Migration.down()
end
