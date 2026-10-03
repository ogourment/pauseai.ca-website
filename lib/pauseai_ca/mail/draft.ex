defmodule PauseAiCa.Mail.Draft do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "mail_drafts" do
    field :batch_id, :binary_id
    field :user_id, :binary_id
    field :email, :string, redact: true
    field :name, :string
    field :variables, :map, default: %{}, redact: true
    field :subject, :string
    field :source, :string, redact: true
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:subject, :source])
    |> validate_required([:subject, :source])
    |> validate_length(:subject, max: 300)
    |> validate_length(:source, max: 50_000)
    |> optimistic_lock(:revision)
  end
end
