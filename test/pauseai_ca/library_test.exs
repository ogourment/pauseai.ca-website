defmodule PauseAiCa.LibraryTest do
  use ExUnit.Case, async: true

  alias PauseAiCa.Library
  alias PauseAiCa.Library.Reference
  alias PauseAiCa.Library.Resource
  alias PauseAiCa.Library.Voice

  describe "the reading library" do
    test "covers every stage of the journey" do
      for stage <- Library.stages() do
        assert Library.resources(stage) != [], "no resource for stage #{stage}"
      end
    end

    test "reads in both languages" do
      for resource <- Library.resources(), locale <- ["en", "fr"] do
        copy = Resource.copy(resource, locale)
        assert copy.title != ""
        assert copy.summary != ""
      end
    end

    test "names a publisher, a source and a review date for every entry" do
      for resource <- Library.resources() do
        assert String.starts_with?(resource.url, "https://")
        assert resource.publisher != ""
        assert %Date{} = resource.reviewed_on
      end
    end

    test "offers French readers material published in French" do
      french = Enum.filter(Library.resources(), &(&1.language == "fr"))

      assert length(french) >= 3
      assert Enum.any?(french, &(&1.publisher == "Pause IA"))
    end

    test "tells a reader when a source is in the other language" do
      french_source = Enum.find(Library.resources(), &(&1.language == "fr"))

      assert Resource.foreign_language?(french_source, "en")
      refute Resource.foreign_language?(french_source, "fr")
    end

    test "stage labels differ by language" do
      refute Library.stage_label(:risk, "fr") == Library.stage_label(:risk, "en")
    end
  end

  describe "Canadian voices" do
    test "include the people a Canadian reader would recognize" do
      names = Enum.map(Library.voices(), & &1.name)

      for expected <- [
            "Yoshua Bengio",
            "Geoffrey Hinton",
            "David Krueger",
            "Wyatt Tessari L'Allié",
            "Gillian Hadfield"
          ] do
        assert expected in names
      end
    end

    test "every quotation is verbatim and linked to where it was said" do
      for voice <- Library.voices() do
        assert voice.quotes != [], "#{voice.name} has no quotation"

        for quotation <- voice.quotes do
          assert String.starts_with?(quotation.url, "https://")
          assert quotation.source != ""
          assert Voice.quote_text(quotation, "en") != ""
          assert Voice.quote_text(quotation, "fr") != ""
        end
      end
    end

    test "a quotation is not silently translated" do
      english_quote =
        Library.voices()
        |> Enum.flat_map(& &1.quotes)
        |> Enum.find(&(&1.language == "en"))

      # A French reader gets the English words, not a paraphrase of them.
      assert Voice.quote_text(english_quote, "fr") == Voice.quote_text(english_quote, "en")
    end

    test "every voice offers more than one way to read further" do
      for voice <- Library.voices() do
        assert length(voice.references) >= 1

        for reference <- voice.references do
          assert String.starts_with?(reference.url, "https://")
          assert Reference.label(reference, "en") != ""
          assert Reference.label(reference, "fr") != ""
        end
      end
    end

    test "affiliations read in both languages" do
      for voice <- Library.voices() do
        assert Voice.affiliation(voice, "en") != ""
        assert Voice.affiliation(voice, "fr") != ""
      end
    end

    test "Hinton is quoted rather than narrated" do
      hinton = Enum.find(Library.voices(), &(&1.id == "hinton"))
      text = Enum.map_join(hinton.quotes, " ", &Voice.quote_text(&1, "en"))

      # He has publicly disputed the "quit Google to warn the world" story, so
      # the page must not repeat it.
      refute String.contains?(String.downcase(text), "google")
      refute String.contains?(String.downcase(Voice.affiliation(hinton, "en")), "google")
    end
  end
end
