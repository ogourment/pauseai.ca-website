defmodule PauseAiCa.CampaignsTest do
  use ExUnit.Case, async: true

  alias PauseAiCa.Campaigns
  alias PauseAiCa.Campaigns.Letter
  alias PauseAiCa.Campaigns.Representative
  alias PauseAiCa.Campaigns.Update
  alias PauseAiCa.Campaigns.WarningShot

  describe "the current warning shot" do
    test "reads in English and in French" do
      campaign = Campaigns.current_warning_shot()

      for locale <- ["en", "fr"] do
        copy = WarningShot.copy(campaign, locale)

        assert copy.title != ""
        assert copy.lede != ""
        assert length(copy.why_bullets) > 0
      end

      refute WarningShot.copy(campaign, "fr").title == WarningShot.copy(campaign, "en").title
    end

    test "presents developments newest first" do
      campaign = Campaigns.current_warning_shot()
      dates = Enum.map(campaign.updates, & &1.date)

      assert dates == Enum.sort(dates, {:desc, Date})
      assert campaign.reviewed_on == ~D[2026-08-29]
    end

    test "every development cites a source a reader can check" do
      for update <- Campaigns.current_warning_shot().updates do
        assert String.starts_with?(update.url, "https://")
        assert update.publisher != ""

        for locale <- ["en", "fr"] do
          copy = Update.copy(update, locale)
          assert copy.title != ""
          assert copy.summary != ""
        end
      end
    end

    test "uses primary sources for the incident and its official follow-ups" do
      updates = Campaigns.current_warning_shot().updates

      assert Enum.any?(updates, &(&1.publisher == "Hugging Face"))
      assert Enum.any?(updates, &(&1.publisher == "OpenAI"))
      assert Enum.any?(updates, &(&1.publisher == "Anthropic"))
      assert Enum.any?(updates, &String.contains?(&1.url, "iowaattorneygeneral.gov"))
      assert Enum.any?(updates, &String.contains?(&1.url, "aisi.gov.uk"))
    end

    test "includes the broader August loss-of-control reporting" do
      assert Enum.any?(Campaigns.current_warning_shot().updates, fn update ->
               update.publisher == "The Guardian" and update.date == ~D[2026-08-29] and
                 String.contains?(update.url, "sharp-rise-in-incidents")
             end)
    end
  end

  describe "finding a member of parliament" do
    test "returns the federal member for a postal code" do
      assert {:ok, [member]} = Campaigns.find_members_of_parliament("h2x 1y4")

      assert member.name == "Steven Guilbeault"
      assert member.district == "Laurier—Sainte-Marie"
      assert member.email == "Steven.Guilbeault@parl.gc.ca"
      assert member.preferred_languages == [:en, :fr]
    end

    test "reads unilingual MPs' preferred language" do
      assert {:ok, [english_member]} = Campaigns.find_members_of_parliament("V7A 5J9")
      assert english_member.name == "Parm Bains"
      assert english_member.preferred_languages == [:en]

      assert {:ok, [french_member]} = Campaigns.find_members_of_parliament("J3B 6X3")
      assert french_member.name == "Christine Normandin"
      assert french_member.preferred_languages == [:fr]
    end

    test "ignores representatives who are not in the House of Commons" do
      {:ok, members} = Campaigns.find_members_of_parliament("H2X1Y4")

      assert Enum.all?(members, &(&1.district == "Laurier—Sainte-Marie"))
    end

    test "rejects input that cannot be a Canadian postal code" do
      assert {:error, :invalid_postal_code} = Campaigns.find_members_of_parliament("90210")
      assert {:error, :invalid_postal_code} = Campaigns.find_members_of_parliament("")
    end

    test "reports when the service knows no such postal code" do
      assert {:error, :not_found} = Campaigns.find_members_of_parliament("X0A 0H0")
    end

    test "reports when the service cannot be reached" do
      assert {:error, :unavailable} = Campaigns.find_members_of_parliament("A1A 1A1")
    end

    test "returns no one when the district has no reachable member" do
      assert {:ok, []} = Campaigns.find_members_of_parliament("K1A 0A6")
    end
  end

  describe "composing a letter" do
    setup do
      %{
        member: %Representative{
          name: "Steven Guilbeault",
          district: "Laurier—Sainte-Marie",
          email: "Steven.Guilbeault@parl.gc.ca"
        }
      }
    end

    test "addresses the member and names the riding", %{member: member} do
      letter =
        Campaigns.compose_letter([member], :en, %{name: "Camille Roy", postal_code: "H2X 1Y4"})

      assert letter.to == "Steven.Guilbeault@parl.gc.ca"
      assert letter.body =~ "Dear Steven Guilbeault,"
      assert letter.body =~ "Laurier—Sainte-Marie"
      assert letter.body =~ "Camille Roy"
      assert letter.body =~ "H2X 1Y4"
    end

    test "writes in French when French is chosen", %{member: member} do
      letter = Campaigns.compose_letter([member], :fr, %{name: "Camille Roy"})

      assert letter.body =~ "Bonjour Steven Guilbeault,"
      refute letter.body =~ "Dear Steven Guilbeault,"
    end

    test "includes both languages in the bilingual draft", %{member: member} do
      letter = Campaigns.compose_letter([member], :bilingual, %{})

      assert letter.body =~ "Dear Steven Guilbeault,"
      assert letter.body =~ "Bonjour Steven Guilbeault,"
    end

    test "leaves a visible placeholder when the sender has not given a name", %{member: member} do
      assert Campaigns.compose_letter([member], :en, %{}).body =~ "[your name]"
      assert Campaigns.compose_letter([member], :fr, %{name: "  "}).body =~ "[votre nom]"
    end

    test "identifies unresolved placeholders before delivery", %{member: member} do
      english = Campaigns.compose_letter([member], :en, %{})
      french = Campaigns.compose_letter([member], :fr, %{name: "  "})
      complete = Campaigns.compose_letter([member], :en, %{name: "Camille Roy"})

      assert PauseAiCa.Campaigns.Letter.unresolved_placeholders?(english)
      assert PauseAiCa.Campaigns.Letter.unresolved_placeholders?(french)
      refute PauseAiCa.Campaigns.Letter.unresolved_placeholders?(complete)
    end

    test "still produces a usable letter when no member was found" do
      letter = Campaigns.compose_letter([], :en, %{})

      assert letter.to == ""
      assert letter.body =~ "Dear Member of Parliament,"
    end

    test "builds a mailto the visitor's mail app can open", %{member: member} do
      letter = Campaigns.compose_letter([member], :en, %{name: "Camille Roy"})
      mailto = Letter.mailto(letter)

      assert String.starts_with?(mailto, "mailto:Steven.Guilbeault@parl.gc.ca?")
      assert mailto =~ "subject="
      assert mailto =~ "body="
      refute mailto =~ " "
    end
  end
end
