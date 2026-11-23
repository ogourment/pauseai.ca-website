defmodule PauseAiCa.Incubators.ChapterPageEdit do
  use Ecto.Schema

  schema "chapter_page_edits" do
    field :page_id, :id
    field :actor_id, :binary_id
    field :revision, :integer
    field :action, :string
    field :content, :map

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
