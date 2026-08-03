defmodule PauseAiCaWeb.LibraryLiveTest do
  use PauseAiCaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "reading the library" do
    test "an English visitor sees every stage and the Canadian voices", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      assert has_element?(view, "#voices")
      assert has_element?(view, "#voice-bengio")
      assert has_element?(view, "#voice-tessari")
      assert has_element?(view, "#voice-hadfield")

      for stage <- PauseAiCa.Library.stages() do
        assert has_element?(view, "#stage-#{stage}")
      end
    end

    test "a French visitor gets the page in French", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/comprendre")

      assert has_element?(view, "#voices")
      assert render(view) =~ "Des voix canadiennes"
    end

    test "French-language sources are offered to French readers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/comprendre")

      assert has_element?(view, "#resource-pauseia-faq a[href^='https://pauseia.fr']")
      assert has_element?(view, "#resource-pauseia-propositions")
    end

    test "the header links to the library and the campaign", %{conn: conn} do
      conn = get(conn, ~p"/en")
      html = html_response(conn, 200)

      assert html =~ "/en/learn"
      assert html =~ "/en/warning-shot"
    end

    test "the Act menu offers the three global asks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      assert has_element?(view, "#act-join[href*='onboarding-form']")
      assert has_element?(view, "#act-sign[href='https://pauseai.info/statement']")
      assert has_element?(view, "#act-actions[href='https://pauseai.info/action']")
    end

    test "the Act menu speaks French on French pages", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/comprendre")

      assert has_element?(view, "#act-join[href*='languages=French']")
      assert render(view) =~ "Signer"
    end

    test "the banner asks about cookies rather than naming a vendor", %{conn: conn} do
      original = Application.get_env(:pauseai_ca, :ga_measurement_id)
      Application.put_env(:pauseai_ca, :ga_measurement_id, "G-TEST123")
      on_exit(fn -> Application.put_env(:pauseai_ca, :ga_measurement_id, original) end)

      {:ok, view, _html} = live(conn, ~p"/en/learn")
      html = render(view)

      assert html =~ "analytics cookies"
      refute html =~ "Google Analytics"
    end

    test "no tracker and no banner without a measurement id", %{conn: conn} do
      original = Application.get_env(:pauseai_ca, :ga_measurement_id)
      Application.put_env(:pauseai_ca, :ga_measurement_id, nil)
      on_exit(fn -> Application.put_env(:pauseai_ca, :ga_measurement_id, original) end)

      {:ok, view, _html} = live(conn, ~p"/en/learn")

      refute has_element?(view, "#consent-banner")
      refute render(view) =~ "googletagmanager"
    end

    test "with a measurement id the banner appears but the tracker does not", %{conn: conn} do
      original = Application.get_env(:pauseai_ca, :ga_measurement_id)
      Application.put_env(:pauseai_ca, :ga_measurement_id, "G-TEST123")
      on_exit(fn -> Application.put_env(:pauseai_ca, :ga_measurement_id, original) end)

      {:ok, view, _html} = live(conn, ~p"/en/learn")
      html = render(view)

      assert has_element?(view, "#consent-banner")
      assert has_element?(view, "#consent-accept")
      assert has_element?(view, "#consent-decline")
      # Law 25: nothing loads until the banner is answered.
      refute html =~ "gtag/js?id=G-TEST123"
    end
  end

  describe "getting updates" do
    test "a consenting visitor is subscribed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      view
      |> form("#subscribe-form", subscribe: %{email: "camille@example.org", consent: "true"})
      |> render_submit()

      assert has_element?(view, "#subscribe-success")
    end

    test "nothing is sent without consent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      view
      |> form("#subscribe-form", subscribe: %{email: "camille@example.org"})
      |> render_submit()

      assert has_element?(view, "#subscribe-error")
      refute has_element?(view, "#subscribe-success")
    end

    test "an address already on the list gets the same friendly answer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/comprendre")

      view
      |> form("#subscribe-form", subscribe: %{email: "taken@example.org", consent: "true"})
      |> render_submit()

      assert has_element?(view, "#subscribe-success")
    end

    test "a bad address is explained rather than swallowed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      view
      |> form("#subscribe-form", subscribe: %{email: "nope", consent: "true"})
      |> render_submit()

      assert has_element?(view, "#subscribe-error")
    end
  end
end
