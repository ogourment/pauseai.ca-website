defmodule PauseAiCa.Repo.Migrations.AddSignupEntryPointToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :signup_entry_point, :string
    end

    create constraint(:users, :users_signup_entry_point_allowlist,
             check:
               "signup_entry_point IS NULL OR signup_entry_point IN ('header', 'home_questions', 'resource_bookmark', 'home_footer', 'unknown')"
           )
  end
end
