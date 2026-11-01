defmodule PauseAiCa.Repo.Migrations.AddInteracDeclarations do
  use Ecto.Migration

  def change do
    create table(:interac_declarations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_ref, references(:users, type: :binary_id)
      add :name, :string
      add :email, :string, null: false
      add :amount_minor, :bigint, null: false
      add :currency, :string, null: false, default: "CAD"
      add :anonymous, :boolean, null: false, default: true
      add :state, :string, null: false, default: "pending"
      add :submission_key, :string
      add :submitted_actor_id, :string, null: false
      add :submitted_at, :utc_datetime_usec, null: false
      add :received_minor, :bigint
      add :received_on, :date
      add :verification_source_ref, :string
      add :bank_reference, :string
      add :verification_note, :text
      add :verified_actor_id, :string
      add :verified_at, :utc_datetime_usec
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:interac_declarations, [:submission_key])

    create unique_index(:interac_declarations, [:verification_source_ref, :bank_reference],
             where: "bank_reference IS NOT NULL",
             name: :interac_declarations_bank_reference_unique
           )

    create index(:interac_declarations, [:state, :inserted_at])
    create index(:interac_declarations, [:email, :inserted_at])

    create constraint(:interac_declarations, :interac_declaration_currency,
             check: "currency = 'CAD'"
           )

    create constraint(:interac_declarations, :interac_declaration_amount,
             check: "amount_minor > 0 AND amount_minor <= 99999999999"
           )

    create constraint(:interac_declarations, :interac_declaration_identity,
             check: "account_ref IS NOT NULL OR (name IS NOT NULL AND length(btrim(name)) > 0)"
           )

    create constraint(:interac_declarations, :interac_declaration_receipt,
             check:
               "(state = 'pending' AND received_minor IS NULL AND received_on IS NULL AND verified_at IS NULL AND verified_actor_id IS NULL) OR (state = 'verified' AND received_minor > 0 AND received_on IS NOT NULL AND verified_at IS NOT NULL AND verified_actor_id IS NOT NULL AND verification_source_ref IS NOT NULL)"
           )

    create constraint(:interac_declarations, :interac_declaration_revision,
             check: "revision >= 1"
           )
  end
end
