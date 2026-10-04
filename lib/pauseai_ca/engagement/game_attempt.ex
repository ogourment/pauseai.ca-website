defmodule PauseAiCa.Engagement.GameAttempt do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "learning_game_attempts" do
    field :visitor_id, Ecto.UUID
    belongs_to :user, PauseAiCa.Accounts.User, type: :binary_id
    field :locale, :string
    field :sequence, :integer, default: 0
    field :furthest_stage, :integer, default: 0
    field :completed, :boolean, default: false
    field :buttons, :map, default: %{}
    timestamps(type: :utc_datetime)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :id,
      :visitor_id,
      :user_id,
      :locale,
      :sequence,
      :furthest_stage,
      :completed,
      :buttons
    ])
    |> validate_required([:id, :visitor_id, :locale, :sequence, :furthest_stage])
    |> validate_inclusion(:locale, ["en", "fr"])
    |> validate_number(:sequence, greater_than_or_equal_to: 0, less_than: 100_000)
    |> validate_number(:furthest_stage, greater_than_or_equal_to: 1, less_than_or_equal_to: 7)
    |> validate_change(:buttons, fn :buttons, buttons ->
      if map_size(buttons) <= 100 and
           Enum.all?(buttons, fn {key, value} ->
             Regex.match?(
               ~r/^[1-7]:(trick|next|swarm|stop|clear|exit|replay|close_copy|choice|close_ally_[1-4]|ally_role_[1-4]|ally_end|bookmark_LEARN-NUGGET-[A-Z-]+|source_opened|learning_path_opened|resource_bookmark_changed)$/,
               key
             ) and is_integer(value) and value >= 0 and value <= 10_000
           end), do: [], else: [buttons: "invalid aggregate"]
    end)
    |> unique_constraint(:id, name: :learning_game_attempts_pkey)
  end
end
