defmodule PauseAiCa.ContactMigration.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contacts" do
    field :email, :string
    field :name, :string
    field :city, :string
    field :source, :string
    field :source_key, :string
    field :source_data, :map, default: %{}
    field :classification, :string, default: "needs_review"
    belongs_to :user, PauseAiCa.Accounts.User
    belongs_to :last_import, PauseAiCa.ContactMigration.Import
    timestamps(type: :utc_datetime)
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :email,
      :name,
      :city,
      :source,
      :source_key,
      :source_data,
      :classification,
      :user_id,
      :last_import_id
    ])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:email, :source, :classification])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/)
    |> validate_inclusion(:classification, ~w(known_active needs_review do_not_contact))
    |> unique_constraint(:email)
  end
end
