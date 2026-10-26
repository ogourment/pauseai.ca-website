defmodule PauseAiCa.Donations.Page do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "donation_pages" do
    field :key, :string, default: "main"
    field :payload, :map, default: %{}
    field :published_payload, :map
    field :published_revision, :integer
    field :published_at, :utc_datetime_usec
    field :revision, :integer, default: 0
    field :updated_by, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:payload, :published_payload, :published_revision, :published_at, :updated_by])
    |> optimistic_lock(:revision)
  end
end

defmodule PauseAiCa.Donations.PageRevision do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "donation_page_revisions" do
    field :page_id, :binary_id
    field :revision, :integer
    field :editor_id, :binary_id
    field :action, :string
    field :payload, :map
    field :published_payload, :map
    field :published_revision, :integer
    field :inserted_at, :utc_datetime_usec
  end
end
