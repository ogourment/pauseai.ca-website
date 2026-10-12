defmodule PauseAiCa.ContactMigration.Activity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contact_activities" do
    field :action, :string
    field :details, :map, default: %{}
    belongs_to :contact, PauseAiCa.ContactMigration.Contact
    belongs_to :actor_user, PauseAiCa.Accounts.User
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:contact_id, :actor_user_id, :action, :details])
    |> validate_required([:contact_id, :action])
    |> validate_actor()
  end

  defp validate_actor(changeset) do
    if get_field(changeset, :actor_user_id) ||
         get_field(changeset, :details, %{})["actor_service"] == "source-intake",
       do: changeset,
       else: add_error(changeset, :actor_user_id, "is required")
  end
end
