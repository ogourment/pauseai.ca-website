defmodule PauseAiCa.Repo.Migrations.AllowVolunteerSignupSource do
  use Ecto.Migration

  def up do
    drop constraint(:users, :users_signup_entry_point_allowlist)

    create constraint(:users, :users_signup_entry_point_allowlist,
             check:
               "signup_entry_point IS NULL OR signup_entry_point IN ('header','home_questions','resource_bookmark','home_footer','unknown','volunteer_signup')"
           )
  end

  def down do
    execute "UPDATE users SET signup_entry_point = 'unknown' WHERE signup_entry_point = 'volunteer_signup'"
    drop constraint(:users, :users_signup_entry_point_allowlist)

    create constraint(:users, :users_signup_entry_point_allowlist,
             check:
               "signup_entry_point IS NULL OR signup_entry_point IN ('header','home_questions','resource_bookmark','home_footer','unknown')"
           )
  end
end
