defmodule PauseAiCa.MPTemplates.Template do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "mp_templates" do
    field :slug, :string
    field :payload, :map, default: %{}
    field :revision, :integer, default: 0
    field :published_revision, :integer
    field :published_at, :utc_datetime_usec
    field :updated_by, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:slug, :payload, :published_revision, :published_at, :updated_by])
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
    |> validate_length(:slug, max: 80)
    |> unique_constraint(:slug)
    |> optimistic_lock(:revision)
  end
end

defmodule PauseAiCa.MPTemplates.Revision do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "mp_template_revisions" do
    field :template_id, :binary_id
    field :revision, :integer
    field :editor_id, :binary_id
    field :action, :string
    field :payload, :map
    field :author_permission, :boolean, default: false
    field :inserted_at, :utc_datetime_usec
  end
end
