defmodule PauseAiCaWeb.WarningShotLiveTest do
  use PauseAiCaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  import PauseAiCa.AccountsFixtures

  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Campaigns.RateLimit
  alias PauseAiCa.Engagement
  alias PauseAiCa.Engagement.Action

  describe "reading the campaign" do
    test "an English visitor sees what happened, what to do, and the developments", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      assert has_element?(view, "#act")
      assert has_element?(view, "#letter")
      assert has_element?(view, "#developments-list")
      assert has_element?(view, "#join-pauseai")
      assert has_element?(view, "#read-analysis")
      assert has_element?(view, "#warning-shot-page-badge")
      refute has_element?(view, "#warning-shot-banner")
      refute has_element?(view, "#campaign-prompt")
      assert render(view) =~ "An AI escaped its lab and hacked a real company"
    end

    test "a French visitor gets the same page in French", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/tir-de-semonce")

      assert has_element?(view, "#act")
      assert has_element?(view, "#developments-list")
      assert render(view) =~ "Tir de semonce"
    end

    test "developments link to the organizations' disclosures and official records", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      assert has_element?(
               view,
               "#update-2026-07-16-hugging-face a[href^='https://huggingface.co']"
             )

      assert has_element?(view, "#update-2026-07-21-openai a[href^='https://openai.com']")

      assert has_element?(
               view,
               "#update-2026-08-03-fifteen-u-s-state-attorneys-general a[href$='.pdf']"
             )
    end

    test "the home page points visitors at the campaign", %{conn: conn} do
      conn = get(conn, ~p"/en")
      html = html_response(conn, 200)

      assert html =~ "/en/warning-shot"
      assert length(Regex.scan(~r/id="warning-shot-banner"/, html)) == 1
    end
  end

  describe "writing to a member of parliament" do
    test "both language pages offer bilingual and single-language letters", %{conn: conn} do
      {:ok, en_view, _html} = live(conn, ~p"/en/warning-shot")

      assert has_element?(
               en_view,
               "#draft-language-options input[type='radio'][value='bilingual']:checked"
             )

      assert has_element?(en_view, "#draft-language-options input[type='radio'][value='en']")
      assert has_element?(en_view, "#draft-language-options input[type='radio'][value='fr']")

      {:ok, fr_view, _html} = live(conn, ~p"/fr/tir-de-semonce")

      assert has_element?(
               fr_view,
               "#draft-language-options input[type='radio'][value='fr']:checked"
             )

      assert has_element?(fr_view, "#draft-language-options", "Bilingue")
      assert has_element?(fr_view, "#draft-language-options", "Anglais seulement")
      assert has_element?(fr_view, "#draft-language-options", "Français seulement")
    end

    test "a postal code produces an editable letter addressed to the MP", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view
      |> form("#mp-lookup-form", sender: %{name: "Camille Roy", postal_code: "H2X 1Y4"})
      |> render_submit()

      assert has_element?(view, "#mp-results")
      assert has_element?(view, "#letter-form")
      assert render(view) =~ "Laurier—Sainte-Marie"
    end

    test "choosing French rewrites the letter without a second lookup", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view
      |> form("#mp-lookup-form", sender: %{name: "Camille Roy", postal_code: "H2X 1Y4"})
      |> render_submit()

      html =
        view
        |> form("#mp-lookup-form",
          sender: %{name: "Camille Roy", postal_code: "H2X 1Y4", draft_language: "fr"}
        )
        |> render_change()

      assert html =~ "Bonjour Steven Guilbeault,"
      refute html =~ "Dear Steven Guilbeault,"
    end

    test "an edited letter is kept for the mailto link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view
      |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"})
      |> render_submit()

      view
      |> form("#letter-form", letter: %{subject: "My own subject", body: "My own words."})
      |> render_change()

      view |> element("#send-mode-diy") |> render_click()

      assert has_element?(view, "#open-mail-app[href*='My%20own%20subject']")
    end

    test "an unverified sender is asked to confirm before anything reaches an MP",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view
      |> form("#mp-lookup-form", sender: %{name: "Camille Roy", postal_code: "H2X 1Y4"})
      |> render_submit()

      view
      |> form("#send-form", send: %{email: "camille@example.org", consent: "true"})
      |> render_submit()

      assert has_element?(view, "#awaiting-confirmation")
      refute has_element?(view, "#send-success")

      # The only mail sent is the confirmation, addressed to the sender.
      assert_email_sent(fn email ->
        assert email.to == [{"", "camille@example.org"}]
        assert email.subject =~ "Confirm and send your letter"
      end)
    end

    test "the confirmation prompt tells people how to rescue it from spam", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view
      |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"})
      |> render_submit()

      html =
        view
        |> form("#send-form", send: %{email: "camille@example.org", consent: "true"})
        |> render_submit()

      assert html =~ "Not spam"
    end

    test "a signed-in supporter with a confirmed address sends straight away", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/en/warning-shot")

      view
      |> form("#mp-lookup-form", sender: %{name: "Camille Roy", postal_code: "H2X 1Y4"})
      |> render_submit()

      view
      |> form("#send-form", send: %{email: user.email, consent: "true"})
      |> render_submit()

      assert has_element?(view, "#send-success")
      assert has_element?(view, "#share-bluesky")
      refute has_element?(view, "#awaiting-confirmation")
    end

    test "sending records a confirmed action for a signed-in supporter", %{conn: conn} do
      user = user_fixture()
      scope = Scope.for_user(user)

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/en/warning-shot")

      view |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"}) |> render_submit()

      view
      |> form("#send-form", send: %{email: user.email, consent: "true"})
      |> render_submit()

      assert [action] = Engagement.list_actions(scope)
      assert action.action_type == "contacted_representative"
      refute Action.pending?(action)
    end

    test "opening your own mail app records an action we cannot vouch for", %{conn: conn} do
      user = user_fixture()
      scope = Scope.for_user(user)

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/en/warning-shot")

      view |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"}) |> render_submit()
      view |> element("#send-mode-diy") |> render_click()
      view |> element("#open-mail-app") |> render_click()

      assert [action] = Engagement.list_actions(scope)
      assert Action.pending?(action)
      assert [^action] = Engagement.list_pending_actions(scope)
      assert has_element?(view, "#diy-handed-over")
    end

    test "the page says letters are diverted before anyone presses send", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"}) |> render_submit()

      assert has_element?(
               view,
               "#rehearsal-notice",
               "Preview: no letter will be sent to your MP."
             )

      assert has_element?(view, "#send-options", "Send your letter")
      assert has_element?(view, "#send-mode-assisted", "Send through PauseAI Canada")
      assert has_element?(view, "#send-mode-diy", "Use my email app")

      html = render(view)
      refute html =~ "Represent (Open North)"
      refute html =~ "reply-to"
    end

    test "a bot that fills the honeypot is not told it was caught", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"}) |> render_submit()

      view
      |> form("#send-form",
        send: %{email: "bot@example.org", consent: "true", website: "https://spam.example"}
      )
      |> render_submit()

      assert has_element?(view, "#send-success")
      refute_email_sent()
    end

    test "an over-long letter is refused", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"}) |> render_submit()

      view
      |> form("#letter-form", letter: %{subject: "Hi", body: String.duplicate("a", 8_001)})
      |> render_change()

      view
      |> form("#send-form", send: %{email: "camille@example.org", consent: "true"})
      |> render_submit()

      assert has_element?(view, "#send-error")
      refute_email_sent()
    end

    test "a burst of letters from one address is refused", %{conn: conn} do
      RateLimit.reset()
      on_exit(&RateLimit.reset/0)

      for attempt <- 1..5 do
        {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

        view |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"}) |> render_submit()

        view
        |> form("#send-form", send: %{email: "flood@example.org", consent: "true"})
        |> render_submit()

        if attempt > 3, do: assert(has_element?(view, "#send-error"))
      end
    end

    test "a French sender chooses how to describe themselves", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/tir-de-semonce")

      view
      |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"})
      |> render_submit()

      html =
        view
        |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4", gender: "feminine"})
        |> render_change()

      assert html =~ "une citoyenne de la circonscription"
      refute html =~ "un·e citoyen·ne de la circonscription"
    end

    test "we never send without explicit authorization", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view
      |> form("#mp-lookup-form", sender: %{name: "Camille Roy", postal_code: "H2X 1Y4"})
      |> render_submit()

      view |> form("#send-form", send: %{email: "camille@example.org"}) |> render_submit()

      assert has_element?(view, "#send-error")
      refute_email_sent()
    end

    test "the DIY path needs no personal data and sends nothing from us", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"}) |> render_submit()
      view |> element("#send-mode-diy") |> render_click()

      assert has_element?(view, "#open-mail-app[href^='mailto:Steven.Guilbeault@parl.gc.ca?']")
      refute has_element?(view, "#send-form")
      refute_email_sent()
    end

    test "a malformed postal code is explained rather than looked up", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view |> form("#mp-lookup-form", sender: %{postal_code: "90210"}) |> render_submit()

      assert has_element?(view, "#lookup-error")
      refute has_element?(view, "#letter-form")
    end

    test "an unavailable lookup service does not break the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view |> form("#mp-lookup-form", sender: %{postal_code: "A1A 1A1"}) |> render_submit()

      assert has_element?(view, "#lookup-error")
      assert has_element?(view, "#developments-list")
    end
  end
end
