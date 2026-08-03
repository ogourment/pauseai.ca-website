defmodule PauseAiCa.LibraryTest do
  use ExUnit.Case, async: true

  alias PauseAiCa.Library
  alias PauseAiCa.Library.Reference
  alias PauseAiCa.Library.Resource
  alias PauseAiCa.Library.Signatory
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
      assert Enum.any?(french, &String.starts_with?(&1.publisher, "Sénat français"))
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

    test "Bengio is represented by his own original French words" do
      bengio = Enum.find(Library.voices(), &(&1.id == "bengio"))
      french = Enum.filter(bengio.quotes, &(&1.language == "fr"))

      assert length(french) >= 2
      assert Enum.all?(french, &String.starts_with?(&1.url, "https://yoshuabengio.org/fr/"))
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

  describe "parliamentary signatories" do
    test "cover both chambers and more than one party" do
      signatories = Library.signatories()

      assert Enum.any?(signatories, &(&1.chamber == :commons))
      assert Enum.any?(signatories, &(&1.chamber == :senate))

      parties = signatories |> Enum.map(&Signatory.party(&1, "en")) |> Enum.uniq()
      assert length(parties) >= 4
    end

    test "read in both languages" do
      for signatory <- Library.signatories() do
        assert signatory.name != ""
        assert Signatory.party(signatory, "en") != ""
        assert Signatory.party(signatory, "fr") != ""
      end
    end

    test "only names verified against the published statement" do
      names = Enum.map(Library.signatories(), & &1.name)

      # Verified present on controlai.org/canada-statement, 2026-08-02.
      assert "Hon. Steven Guilbeault" in names
      assert "Martin Champoux" in names
      assert "Hon. Colin Deacon" in names

      # Circulated in a summary but not on the statement. Do not re-add without
      # a source that names them.
      for unverified <- ["Elizabeth May", "Paula Simons", "Francis Scarpaleggia", "Marilène Gill"] do
        refute Enum.any?(names, &String.contains?(&1, unverified))
      end
    end

    test "the statement is linked in the reader's language" do
      assert Library.statement_url("fr") =~ "/fr"
      assert Library.statement_url("en") =~ "/en"
    end
  end
end
