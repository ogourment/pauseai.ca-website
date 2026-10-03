defmodule PauseAiCa.Mail.Batch do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "mail_batches" do
    field :owner_id, :binary_id
    field :anchor_user_id, :binary_id
    field :recipient_ids, {:array, :binary_id}, default: []
    field :subject, :string, default: ""
    field :source, :string, default: "", redact: true
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [:subject, :source, :recipient_ids])
    |> validate_length(:subject, max: 300)
    |> validate_length(:source, max: 50_000)
    |> validate_length(:recipient_ids, min: 1, max: 5)
    |> optimistic_lock(:revision)
  end
end
