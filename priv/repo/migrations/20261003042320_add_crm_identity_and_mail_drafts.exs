defmodule PauseAiCa.Repo.Migrations.AddCrmIdentityAndMailDrafts do
  use Ecto.Migration

  def up do
    PhoenixCRM.Migration.up()

    create table(:crm_contact_links, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :contact_id, references(:contacts, type: :uuid, on_delete: :restrict), null: false
      add :person_id, references(:crm_people, type: :uuid, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:crm_contact_links, [:contact_id])
    create index(:crm_contact_links, [:person_id])

    create table(:mail_batches, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :anchor_user_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :recipient_ids, {:array, :uuid}, null: false, default: []
      add :subject, :text, null: false, default: ""
      add :source, :text, null: false, default: ""
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create index(:mail_batches, [:owner_id, :updated_at])

    create constraint(:mail_batches, :mail_batches_recipient_limit,
             check: "cardinality(recipient_ids) BETWEEN 1 AND 5"
           )

    create table(:mail_drafts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :batch_id, references(:mail_batches, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :email, :string, null: false
      add :name, :string
      add :variables, :map, null: false, default: %{}
      add :subject, :text, null: false
      add :source, :text, null: false
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:mail_drafts, [:batch_id, :user_id])
  end

  def down do
    drop table(:mail_drafts)
    drop table(:mail_batches)
    drop table(:crm_contact_links)
    PhoenixCRM.Migration.down()
  end
end
