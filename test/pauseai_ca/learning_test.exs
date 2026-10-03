defmodule PauseAiCa.LearningTest do
  use ExUnit.Case, async: true

  test "LEARN-REQ-04 language affinity reorders sources while preserving concept identity" do
    french = PauseAiCa.Learning.nuggets("fr")
    english = PauseAiCa.Learning.nuggets("en")
    assert hd(french)["id"] == "bengio-speed"
    assert hd(english)["id"] == "future-systems"
    assert Enum.sort(Enum.map(french, & &1["id"])) == Enum.sort(Enum.map(english, & &1["id"]))

    for edition <- [french, english] do
      speed = Enum.find(edition, &(&1["id"] == "bengio-speed"))
      assert speed["url"] == "https://www.youtube.com/watch?v=WSsggkm03uE&t=100s"
      assert speed["answer"] =~ "Bengio"
      future = Enum.find(edition, &(&1["id"] == "future-systems"))
      assert future["url"] =~ "/intro/"
    end
  end
end
