defmodule PauseAiCa.Assistant.Instruction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  schema "assistant_instructions" do
    field :source, :string
    field :published_source, :string
    field :revision, :integer, default: 0
    field :published_revision, :integer
    field :updated_by, :binary_id
    field :published_by, :binary_id
    field :published_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, [
      :source,
      :published_source,
      :published_revision,
      :updated_by,
      :published_by,
      :published_at
    ])
    |> validate_required([:source])
    |> validate_length(:source, max: 24_000, count: :bytes)
    |> optimistic_lock(:revision)
  end
end

defmodule PauseAiCa.Assistant.InstructionRevision do
  use Ecto.Schema

  schema "assistant_instruction_revisions" do
    field :revision, :integer
    field :editor_id, :binary_id
    field :action, :string
    field :source, :string
    field :published_source, :string
    field :published_revision, :integer
    field :inserted_at, :utc_datetime_usec
  end
end
