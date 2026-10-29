defmodule PauseAiCa.Blog.Article do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "blog_articles" do
    field :slug, :string
    field :payload, :map, default: %{}
    field :published_payload, :map
    field :published_revision, :integer
    field :published_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    field :revision, :integer, default: 0
    field :updated_by, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(article, attrs) do
    article
    |> cast(attrs, [
      :slug,
      :payload,
      :published_payload,
      :published_revision,
      :published_at,
      :archived_at,
      :updated_by
    ])
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
    |> validate_length(:slug, max: 100)
    |> unique_constraint(:slug)
    |> optimistic_lock(:revision)
  end
end

defmodule PauseAiCa.Blog.Revision do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "blog_article_revisions" do
    field :article_id, :binary_id
    field :revision, :integer
    field :editor_id, :binary_id
    field :action, :string
    field :payload, :map
    field :published_payload, :map
    field :published_revision, :integer
    field :inserted_at, :utc_datetime_usec
  end
end
