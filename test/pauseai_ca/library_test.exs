defmodule PauseAiCa.LibraryTest do
  use ExUnit.Case, async: true

  alias PauseAiCa.Library
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

    test "every quotation is attributed to a source a reader can open" do
      for voice <- Library.voices() do
        assert String.starts_with?(voice.url, "https://")
        assert voice.source != ""

        for locale <- ["en", "fr"] do
          assert Voice.text(voice, :quote, locale) != ""
          assert Voice.text(voice, :affiliation, locale) != ""
        end
      end
    end
  end
end
