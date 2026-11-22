defmodule PauseAiCa.Incubators.ChapterEdit do
  use Ecto.Schema

  schema "chapter_edits" do
    field :group_id, :binary_id
    field :actor_id, :binary_id
    field :revision, :integer
    field :action, :string
    field :content, :map
  end
end
