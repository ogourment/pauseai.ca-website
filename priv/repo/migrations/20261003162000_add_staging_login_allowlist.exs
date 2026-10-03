defmodule PauseAiCa.Repo.Migrations.AddStagingLoginAllowlist do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :staging_login_allowed, :boolean, null: false, default: false
    end
  end
end
