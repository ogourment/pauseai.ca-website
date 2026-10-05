defmodule PauseAiCa.Repo.Migrations.LinkPreexistingContactIdentities do
  use Ecto.Migration

  def up do
    case PauseAiCa.CRM.LegacyUpgrade.run(repo()) do
      {:ok, _count} -> :ok
      {:error, reason} -> raise "Historical contact identity upgrade failed: #{inspect(reason)}"
    end
  end

  # Keep additive identity/provenance on application rollback. Deleting identities
  # could discard subsequent human edits or reconciliation; old releases ignore them.
  def down, do: :ok
end
