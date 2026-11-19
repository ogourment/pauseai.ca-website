defmodule PauseAiCa.Incubators.Responsibility do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "group_responsibilities" do
    belongs_to :membership, PauseAiCa.Incubators.Membership
    field :title, :string
    field :starts_on, :date
    field :ends_on, :date
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
