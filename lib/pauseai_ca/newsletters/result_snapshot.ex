defmodule PauseAiCa.Newsletters.ResultSnapshot do
  use Ecto.Schema
  @primary_key false
  schema "newsletter_result_snapshots" do
    field :batch_id, :binary_id, primary_key: true
    field :observed, :map
    field :partial, :boolean
    field :refreshed_at, :utc_datetime_usec
  end
end
