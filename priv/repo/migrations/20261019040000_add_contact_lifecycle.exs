defmodule PauseAiCa.Repo.Migrations.AddContactLifecycle do
  use Ecto.Migration
  def up, do: PhoenixCRM.ContactLifecycleMigration.up()
  def down, do: PhoenixCRM.ContactLifecycleMigration.down()
end
