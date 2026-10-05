defmodule PauseAiCa.Newsletters.Draft do
  @moduledoc "Consumer-owned authored newsletter content. A draft cannot authorize delivery."
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "newsletter_drafts" do
    field :owner_id, :binary_id
    field :subject, :string, default: ""
    field :source, :string, default: "", redact: true
    field :region, :string, default: ""
    field :revision, :integer, default: 1
    field :archived_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:subject, :source, :region])
    |> validate_length(:subject, max: 300)
    |> validate_length(:source, max: 50_000)
    |> validate_inclusion(:region, ["", "Montréal", "ROQuébec", "ROCanada"])
  end
end
