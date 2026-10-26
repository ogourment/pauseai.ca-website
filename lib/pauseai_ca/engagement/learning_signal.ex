defmodule PauseAiCa.Engagement.LearningSignal do
  @moduledoc """
  First-party signals deduplicated by browser, kind and subject.

  `donation_link_opened` with subject `manifund` counts unique browsers that
  opened the donation link. It does not count clicks, donors, payments or amounts.
  `brochure_opened` with subject `brochure` separately counts unique browsers
  opening the brochure link, without measuring a PDF download or completed read.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(question_answered questionnaire_completed learn_page_visited resource_opened resource_bookmarked event_link_opened donation_link_opened brochure_opened)

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
