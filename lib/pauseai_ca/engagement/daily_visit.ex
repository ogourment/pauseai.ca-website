defmodule PauseAiCa.Engagement.DailyVisit do
  use Ecto.Schema

  @primary_key {:visited_on, :date, autogenerate: false}
  schema "daily_visits" do
    field :count, :integer
  end
end
