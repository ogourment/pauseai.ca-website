defmodule PauseAiCa.ContactMigration.Import do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contact_imports" do
    field :filename, :string
    field :source, :string
    field :selected_count, :integer, default: 0
    belongs_to :imported_by, PauseAiCa.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def changeset(import, attrs) do
    import
    |> cast(attrs, [:filename, :source, :selected_count, :imported_by_id])
    |> validate_required([:filename, :source, :selected_count, :imported_by_id])
  end
end
