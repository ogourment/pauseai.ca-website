defmodule PauseAiCa.Assistant.CanadianReferencesTest do
  use ExUnit.Case, async: true
  alias PauseAiCa.Assistant.CanadianReferences
  alias PhoenixAgentAssistant.{Canonical, Context}

  test "pinned public reference contains the complete declared locality filter and boundary warnings" do
    reference = CanadianReferences.vancouver()

    assert reference["candidate_fsas"] ==
             ~w(V5K V5L V5M V5N V5P V5R V5S V5T V5V V5W V5X V5Y V5Z V6A V6B V6C V6E V6G V6H V6J V6K V6L V6M V6N V6P V6R V6S V6T V6Z V7X V7Y)

    assert length(Enum.uniq(reference["candidate_fsas"])) == 31
    assert reference["source"]["matched_rows"] == 31

    assert reference["source"]["archive_sha256"] ==
             "5f6237799474d75fa53c9294ab6c469e8ce7f680034fca4b219aeeb1fdad1917"

    assert reference["source"]["licence"] == "CC BY 4.0"
    assert reference["municipal_coverage_verified"] == false

    assert reference["city_demo"] == %{
             "field" => "cities",
             "values" => ["Vancouver"],
             "uses_candidate_fsas" => false
           }

    assert Enum.find(reference["boundary_warnings"], &(&1["fsa"] == "V6T"))["treatment"] ==
             "exclude_from_city_only"

    assert Enum.find(reference["boundary_warnings"], &(&1["fsa"] == "V6S"))["treatment"] ==
             "municipal_overlap_review_required"

    assert CanadianReferences.digest() == Canonical.digest(reference)
    assert byte_size(Canonical.encode(CanadianReferences.context())) < 8_192
  end

  test "reference participates in the full escaped request size bound before history is added" do
    request = %{
      "text" => String.duplicate("\\\"é", 800),
      "context" => %{"canadian_references" => CanadianReferences.context()},
      "attachments" => []
    }

    history =
      for _ <- 1..20, do: %{"role" => "assistant", "text" => String.duplicate("\\\"é", 2_000)}

    assert {:ok, bounded} = Context.with_history(request, history)
    assert byte_size(Canonical.encode(bounded)) <= 40_000
    assert bounded["text"] == request["text"]
    assert bounded["context"]["canadian_references"] == CanadianReferences.context()

    assert {:error, :request_too_large} =
             Context.with_history(request, [], byte_size(Canonical.encode(request)) - 1)
  end
end
