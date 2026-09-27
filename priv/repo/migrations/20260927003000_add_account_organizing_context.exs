defmodule PauseAiCa.Repo.Migrations.AddAccountOrganizingContext do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :organizing_group_id,
          references(:volunteer_groups, type: :binary_id, on_delete: :restrict)

      add :organizer_notes, :text, null: false, default: ""
    end

    create index(:users, [:organizing_group_id])

    execute """
    UPDATE users AS u SET organizing_group_id = s.group_id, organizer_notes = s.notes
    FROM volunteer_signups AS s WHERE s.user_id = u.id
    """
  end

  def down do
    alter table(:users) do
      remove :organizing_group_id
      remove :organizer_notes
    end
  end
end
