defmodule PauseAiCa.Incubators.ChapterPage do
  use Ecto.Schema

  schema "chapter_pages" do
    field :group_id, :binary_id
    field :slug, :string
    field :revision, :integer, default: 1
    field :draft, :map
    field :published, :map

    timestamps(type: :utc_datetime)
  end
end
