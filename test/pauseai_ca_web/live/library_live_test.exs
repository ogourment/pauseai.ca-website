defmodule PauseAiCaWeb.LibraryLiveTest do
  use PauseAiCaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "reading the library" do
    test "an English visitor sees every stage and the Canadian voices", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      assert has_element?(
               view,
               "#montreal-protest-banner[href='/en/montreal-protest-2026-09-26']"
             )

      assert has_element?(view, "#warning-shot-banner[href='/en/warning-shot']")
      assert render(view) =~ "September 26 · Read the recap"
      assert has_element?(view, "#campaign-prompt[data-campaign='warning-shot-2']")
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

      assert has_element?(view, "#announcement-banners > #montreal-protest-banner:first-child")
      assert has_element?(view, "#announcement-banners > #warning-shot-banner:last-child")
      assert has_element?(view, "#voices")
      assert has_element?(view, "#voice-saba")
      assert has_element?(view, "#voice-guay")
      html = render(view)
      assert html =~ "26 septembre · Lire le compte rendu"
      assert html =~ "Des voix canadiennes"
    end

    test "the statement roster includes new supporters and identifies former MPs", %{conn: conn} do
      for {route, former, former_female} <- [
            {"/en/learn", "Former MP", "Former MP"},
            {"/fr/comprendre", "Ancien député", "Ancienne députée"}
          ] do
        {:ok, view, _html} = live(conn, route)

        for name <- ["Grant Jackson", "Tracy Muggli", "Jeremy Patzer", "Julie Miville-Dechêne"] do
          assert has_element?(view, "#parliament li", name)
        end

        for {name, label} <- [
              {"Jonathan Wilkinson", former},
              {"Steven Guilbeault", former},
              {"Simon-Pierre Savard-Tremblay", former},
              {"Cathay Wagantall", former_female}
            ] do
          row = view |> element("#parliament li", name) |> render()
          assert row =~ label
        end
      end
    end

    test "the legacy French learn route opens the French-first edition", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/learn")

      assert has_element?(view, "#voice-saba")
      assert render(view) =~ "Faut-il ralentir l&#39;IA?"
    end

    test "French-language sources are offered to French readers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/comprendre")

      assert has_element?(view, "#resource-pauseia-faq a[href='/learning/resources/pauseia-faq']")
      assert has_element?(view, "#resource-pauseia-propositions")
    end

    test "every reviewed resource can be bookmarked", %{conn: conn} do
      {:ok, anonymous_view, _html} = live(conn, ~p"/en/learn")

      for resource <- PauseAiCa.Library.resources() do
        assert has_element?(
                 anonymous_view,
                 "#resource-#{resource.id} a[href='/users/register?bookmark=#{resource.id}&locale=en']"
               )
      end

      user = PauseAiCa.AccountsFixtures.user_fixture()
      {:ok, signed_in_view, _html} = conn |> log_in_user(user) |> live(~p"/en/learn")

      for resource <- PauseAiCa.Library.resources() do
        assert has_element?(
                 signed_in_view,
                 "#resource-#{resource.id} a[href='/bookmarks/#{resource.id}?locale=en']"
               )
      end
    end

    test "the header links to the library and the campaign", %{conn: conn} do
      conn = get(conn, ~p"/en")
      html = html_response(conn, 200)

      assert html =~ "/en/learn"
      assert html =~ "/en/warning-shot"
    end

    test "the menu is named the way PauseAI Global names it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")
      assert render(view) =~ "Get involved"

      {:ok, fr_view, _html} = live(conn, ~p"/fr/comprendre")
      assert render(fr_view) =~ "S&#39;impliquer"
    end

    test "the Get involved menu offers the three global asks, in a new tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      assert has_element?(view, "#involvement-menu a[href='/en/strategy']", "Strategy")

      assert has_element?(
               view,
               "#involvement-menu a[href='/en/strategy#engagement-ladder']",
               "Ways to take part"
             )

      assert has_element?(
               view,
               "#involvement-menu a[href='/en/learn#local-participation']",
               "Join or start a group"
             )

      assert has_element?(
               view,
               "#involvement-menu a[href='https://luma.com/calendar/cal-tsYv79s4aTQC16Q']",
               "Events"
             )

      assert has_element?(view, "#act-join[href='/en/learn#updates']", "Stay informed")

      assert has_element?(
               view,
               "#act-email-mp[href='/en/warning-shot#letter']",
               "Email your MP"
             )

      # External actions route through the app so a departure can be recorded,
      # and open in a new tab so a reader does not lose their place.
      assert has_element?(view, "#act-sign[href='/act/sign?locale=en'][target='_blank']")
      assert has_element?(view, "#act-actions[href='/act/actions?locale=en'][target='_blank']")
    end

    test "About follows the involvement menu and events are inside it", %{conn: conn} do
      html = conn |> get(~p"/en") |> html_response(200)

      assert html =~ ~r/id="involvement-menu".*href="\/en\/about"/s
      refute html =~ ~r/id="involvement-menu".*<\/details>.*href="https:\/\/luma.com\/calendar/s
    end

    test "a signed-in visitor gets one account menu", %{conn: conn} do
      user = PauseAiCa.AccountsFixtures.user_fixture()
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/en/learn")

      assert has_element?(view, "#account-menu", user.email)
      assert has_element?(view, "#account-menu a[href='/en/dashboard']", "My dashboard")
      assert has_element?(view, "#account-menu a[href='/en/profile']", "My profile")
      assert has_element?(view, "#account-menu a[href='/users/settings']", "Settings")

      assert has_element?(
               view,
               "#account-menu a[href='/users/settings#password_form']",
               "Change password"
             )

      assert has_element?(
               view,
               "#account-menu a[href='/fr/comprendre']",
               "Français"
             )

      assert has_element?(view, "#account-menu a[href='/users/log-out']", "Log out")
      assert has_element?(view, "#account-menu [role='separator']")
    end

    test "the Act menu speaks French on French pages", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/comprendre")

      assert has_element?(
               view,
               "#act-join[href='/fr/comprendre#updates']",
               "Rester au courant"
             )

      assert has_element?(
               view,
               "#act-email-mp[href='/fr/signal-d-alarme#letter']",
               "Écrire à votre député·e"
             )

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
    test "LEARN-REQ-05 subscription asks for email and consent before location", %{conn: conn} do
      for path <- ["/en/learn", "/fr/comprendre"] do
        {:ok, view, _} = live(conn, path)
        assert has_element?(view, "#subscribe-form input[type=email]")
        refute has_element?(view, "#subscribe-form input[autocomplete=postal-code]")
        refute has_element?(view, "#subscribe-form input[autocomplete=address-level2]")
        assert has_element?(view, "#local-interest-form input[autocomplete=postal-code]")
      end
    end

    test "consent links to the confidentiality policy on the same site", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      assert has_element?(
               view,
               "#subscribe-form a[href='/en/privacy']",
               "Read our privacy policy."
             )
    end

    test "a consenting visitor is subscribed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      view
      |> form("#subscribe-form", subscribe: %{email: "camille@example.org", consent: "true"})
      |> render_submit()

      assert has_element?(view, "#subscribe-success")
    end

    test "LEARN-REQ-08 anonymous local interest does not create an account", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/fr/comprendre")
      before = PauseAiCa.Repo.aggregate(PauseAiCa.Accounts.User, :count)
      view |> form("#local-interest-form", local: %{fsa: "H2X"}) |> render_submit()
      assert has_element?(view, "#local-paths")
      refute has_element?(view, "#local-interest-success")
      assert PauseAiCa.Repo.aggregate(PauseAiCa.Accounts.User, :count) == before
    end

    test "LEARN-REQ-08 invalid local input preserves the task", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/en/learn")
      view |> form("#local-interest-form", local: %{fsa: "123"}) |> render_submit()
      refute has_element?(view, "#local-paths")
      assert has_element?(view, "#local-interest-form input[value='123']")
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
