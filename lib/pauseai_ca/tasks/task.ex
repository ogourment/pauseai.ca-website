defmodule PauseAiCa.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "organizer_tasks" do
    belongs_to :group, PauseAiCa.Volunteers.Group
    belongs_to :requester, PauseAiCa.Accounts.User
    belongs_to :accountable, PauseAiCa.Accounts.User
    belongs_to :assignee, PauseAiCa.Accounts.User
    belongs_to :backup, PauseAiCa.Accounts.User
    field :title, :string
    field :description, :string, default: ""
    field :status, :string, default: "open"
    field :source, :string, default: "manual"
    field :due_date, :date
    field :revision, :integer, default: 1
    field :prerequisite_ids, {:array, :binary_id}, virtual: true, default: []
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :description,
      :accountable_id,
      :assignee_id,
      :backup_id,
      :due_date,
      :status,
      :prerequisite_ids
    ])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :status])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 20_000)
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:requester_id)
    |> foreign_key_constraint(:accountable_id)
    |> foreign_key_constraint(:assignee_id)
    |> foreign_key_constraint(:backup_id)
  end
end
