defmodule PauseAiCa.Engagement.LadderTest do
  use ExUnit.Case, async: true

  alias PauseAiCa.Engagement.{Action, Ladder}

  test "moves from learning toward recursive organizing" do
    assert Ladder.recommendation([], "en").title == "Understand one argument"

    assert Ladder.recommendation([%Action{action_type: "learned"}], "en").title ==
             "Talk with one person"

    actions =
      ~w(learned conversation event contacted_representative volunteered)
      |> Enum.map(&%Action{action_type: &1})

    assert Ladder.recommendation(actions, "en").title == "Bring people together"
  end

  test "provides French-first recommendations" do
    assert Ladder.recommendation([], "fr").title == "Comprendre un argument"
  end
end
