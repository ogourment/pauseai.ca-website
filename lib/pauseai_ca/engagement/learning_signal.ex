defmodule PauseAiCa.Engagement.LearningSignal do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(question_answered questionnaire_completed learn_page_visited resource_opened resource_bookmarked)

  schema "learning_signals" do
    field :visitor_id, Ecto.UUID
    field :kind, :string
    field :subject, :string, default: ""
    field :value, :string
    belongs_to :user, PauseAiCa.Accounts.User, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [:visitor_id, :user_id, :kind, :subject, :value])
    |> validate_required([:visitor_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint([:visitor_id, :kind, :subject])
  end
end
