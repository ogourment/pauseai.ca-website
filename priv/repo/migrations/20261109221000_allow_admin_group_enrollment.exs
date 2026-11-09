defmodule PauseAiCa.Repo.Migrations.AllowAdminGroupEnrollment do
  use Ecto.Migration

  def up do
    alter table(:incubator_memberships) do
      modify :conduct_at, :utc_datetime_usec, null: true
    end
  end

  def down do
    # PostgreSQL refuses this change while unacknowledged enrollments exist.
    # A rollback must preserve those records without inventing acknowledgements.
    alter table(:incubator_memberships) do
      modify :conduct_at, :utc_datetime_usec, null: false
    end
  end
end
