defmodule PauseAiCaWeb.WarningShotLiveTest do
  use PauseAiCaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias PauseAiCa.Campaigns.RateLimit

  describe "reading the campaign" do
    test "an English visitor sees what happened, what to do, and the developments", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      assert has_element?(view, "#act")
      assert has_element?(view, "#letter")
      assert has_element?(view, "#developments-list")
      assert has_element?(view, "#join-pauseai")
      assert has_element?(view, "#read-analysis")
      assert render(view) =~ "An AI escaped its lab and hacked a real company"
    end

    test "a French visitor gets the same page in French", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/tir-de-semonce")

      assert has_element?(view, "#act")
      assert has_element?(view, "#developments-list")
      assert render(view) =~ "Tir de semonce"
    end

    test "developments link out to their original reporting", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      assert has_element?(view, "#update-2026-07-21-fortune a[href^='https://fortune.com']")
      assert has_element?(view, "#update-2026-07-29-la-presse a[href^='https://www.lapresse.ca']")
    end

    test "the home page points visitors at the campaign", %{conn: conn} do
      conn = get(conn, ~p"/en")

      assert html_response(conn, 200) =~ "/en/warning-shot"
    end
  end

  describe "writing to a member of parliament" do
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

    test "a consenting supporter can have us send it for them", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view
      |> form("#mp-lookup-form", sender: %{name: "Camille Roy", postal_code: "H2X 1Y4"})
      |> render_submit()

      view
      |> form("#send-form", send: %{email: "camille@example.org", consent: "true"})
      |> render_submit()

      assert has_element?(view, "#send-success")

      # Rehearsal mode is on outside production, so it lands with the sender.
      assert_email_sent(fn email ->
        assert email.reply_to == {"Camille Roy", "camille@example.org"}
        assert email.to == [{"", "camille@example.org"}]
      end)
    end

    test "sending offers a way to bring someone else in", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view
      |> form("#mp-lookup-form", sender: %{name: "Camille Roy", postal_code: "H2X 1Y4"})
      |> render_submit()

      view
      |> form("#send-form", send: %{email: "camille@example.org", consent: "true"})
      |> render_submit()

      assert has_element?(view, "#share-bluesky")
      assert has_element?(view, "#share-email")
    end

    test "the page says letters are diverted before anyone presses send", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/warning-shot")

      view |> form("#mp-lookup-form", sender: %{postal_code: "H2X 1Y4"}) |> render_submit()

      assert has_element?(view, "#rehearsal-notice")
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
