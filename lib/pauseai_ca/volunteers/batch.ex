defmodule PauseAiCa.Volunteers.Batch do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "volunteer_batches" do
    belongs_to :owner, PauseAiCa.Accounts.User
    belongs_to :default_group, PauseAiCa.Volunteers.Group
    field :csv_mapping, :map, default: %{}
    field :entry_mode, :string, default: "multiple"
    field :source, :string, default: ""
    field :state, :string, default: "draft"
    field :step, :string, default: "rows"
    field :wizard_row, :string
    field :rows, {:array, :map}, default: []
    field :version, :integer, default: 1
    timestamps(type: :utc_datetime)
  end
end
