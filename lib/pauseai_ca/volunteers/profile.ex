defmodule PauseAiCa.Volunteers.Profile do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "volunteer_profiles" do
    belongs_to :user, PauseAiCa.Accounts.User
    field :details, :map, default: %{}
    field :draft, :map, default: %{}
    field :step, :string, default: "contact"
    timestamps(type: :utc_datetime)
  end
end
