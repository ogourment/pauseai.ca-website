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
    field :recipient_mode, :string, default: "newsletter"
    field :recipient_keys, {:array, :string}, default: []
    field :revision, :integer, default: 1
    field :archived_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:subject, :source, :region, :recipient_mode, :recipient_keys])
    |> update_change(:recipient_keys, fn keys ->
      keys
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn key ->
        case Ecto.UUID.cast(key) do
          {:ok, uuid} -> uuid
          _ -> key
        end
      end)
      |> Enum.uniq()
    end)
    |> validate_length(:recipient_keys, max: 5000)
    |> validate_change(:recipient_keys, fn field, keys ->
      if Enum.all?(keys, &match?({:ok, _}, Ecto.UUID.cast(&1))),
        do: [],
        else: [{field, "is invalid"}]
    end)
    |> validate_inclusion(:recipient_mode, ["contacts", "newsletter"])
    |> validate_length(:subject, max: 300)
    |> validate_length(:source, max: 50_000)
    |> validate_inclusion(:region, ["", "Montréal", "ROQuébec", "ROCanada"])
  end
end
