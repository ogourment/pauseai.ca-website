defmodule PauseAiCa.Repo.Migrations.InstallAcceptanceHarnessAdminStore do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    AcceptanceHarness.AdminStore.install!(PauseAiCa.Repo)
  end

  # Acceptance evidence and reviewer comments are operational records. Keep
  # them intact if the application migration is rolled back.
  def down, do: :ok
end
