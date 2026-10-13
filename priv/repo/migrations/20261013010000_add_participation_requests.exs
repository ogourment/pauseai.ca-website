defmodule PauseAiCa.Repo.Migrations.AddParticipationRequests do
  use Ecto.Migration

  def change do
    create table(:participation_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :text, null: false
      add :name, :text
      add :fsa, :text
      add :city, :text
      add :help_text, :text
      add :locale, :text, null: false
      add :newsletter, :boolean, null: false, default: false
      add :account, :boolean, null: false, default: false
      add :local_kind, :text
      add :state, :text, null: false, default: "pending"
      add :delivery_state, :text, null: false, default: "reserved"
      add :confirmation_hash, :binary
      add :withdrawal_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :confirmed_at, :utc_datetime_usec
      add :withdrawn_at, :utc_datetime_usec
      add :context, :map, null: false, default: %{}
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :followup_owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create index(:participation_requests, [:email, :inserted_at])

    create unique_index(:participation_requests, [:confirmation_hash],
             where: "confirmation_hash IS NOT NULL"
           )

    create unique_index(:participation_requests, [:withdrawal_hash])
    create index(:participation_requests, [:state, :local_kind])
  end
end
