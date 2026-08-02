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
