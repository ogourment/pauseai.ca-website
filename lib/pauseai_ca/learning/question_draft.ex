defmodule PauseAiCa.Learning.QuestionDraft do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "quiz_question_drafts" do
    field :review_id, :string
    field :concept_id, :string
    field :topic, :string, default: "actions"
    field :kind, :string, default: "factual"
    field :status, :string, default: "draft"
    field :editions, :map, default: %{}
    field :published_editions, :map, default: %{}
    field :published_kind, :string
    field :published_topic, :string
    field :published_revision, :integer
    field :published_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
    field :revision, :integer, default: 1
    field :updated_by, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [
      :review_id,
      :concept_id,
      :topic,
      :kind,
      :editions,
      :updated_by,
      :status,
      :published_editions,
      :published_kind,
      :published_topic,
      :published_revision,
      :published_at,
      :deleted_at
    ])
    |> validate_required([:review_id, :concept_id])
    |> validate_length(:review_id, max: 100)
    |> validate_length(:concept_id, max: 100)
    |> validate_length(:topic, max: 100)
    |> validate_inclusion(:topic, ~w(actions research incidents voices politics treaty))
    |> validate_inclusion(:kind, ~w(factual opinion planning discussion))
    |> validate_inclusion(:status, ~w(draft published))
    |> unique_constraint(:review_id)
    |> unique_constraint(:concept_id)
    |> optimistic_lock(:revision)
  end
end

defmodule PauseAiCa.Learning.QuestionRevision do
  use Ecto.Schema

  schema "quiz_question_revisions" do
    field :question_id, :binary_id
    field :revision, :integer
    field :editor_id, :binary_id
    field :editions, :map
    field :kind, :string
    field :topic, :string
    field :status, :string
    field :published_editions, :map
    field :inserted_at, :utc_datetime_usec
  end
end
