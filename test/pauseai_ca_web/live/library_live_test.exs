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
      assert has_element?(view, "#campaign-prompt[data-campaign='rogue-agent-1']")
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

    test "the Get involved menu focuses on solo actions, local requests and events", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/en/learn")

      assert has_element?(
               view,
               "#act-solo[href='/en/participate?intent=account']",
               "Record my actions"
             )

      assert has_element?(
               view,
               "#act-local[href='/en/participate?intent=waitlist']",
               "Join or help a local group"
             )

      assert has_element?(
               view,
               "#involvement-menu a[href='https://luma.com/calendar/cal-tsYv79s4aTQC16Q'][target='_blank']",
               "Events"
             )

      refute has_element?(view, "#involvement-menu a[href='/en/strategy']")
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

    test "the focused participation menu speaks French", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/fr/comprendre")

      assert has_element?(
               view,
               "#act-solo[href='/fr/participer?intent=account']",
               "Noter mes actions"
             )

      assert has_element?(
               view,
               "#act-local[href='/fr/participer?intent=waitlist']",
               "Rejoindre ou aider un groupe local"
             )
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
    test "LEARN-REQ-05 subscription collects email, consent and a compact local area", %{
      conn: conn
    } do
      for path <- ["/en/learn", "/fr/comprendre"] do
        {:ok, view, _} = live(conn, path)
        assert has_element?(view, "#participation-form input[type=email]")
        refute has_element?(view, "#participation-form input[autocomplete=postal-code]")
        refute has_element?(view, "#participation-form input[autocomplete=address-level2]")
        assert has_element?(view, "#participation-form input[name='participation[location]']")

        assert has_element?(
                 view,
                 "#participation-form input[name='participation[account]'][type=checkbox]"
               )
      end
    end

    test "consent links to the confidentiality policy on the same site", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      assert has_element?(
               view,
               "#participation-form a[href='/en/privacy']",
               "Read our privacy policy."
             )
    end

    test "a consenting visitor stays pending until email confirmation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      view
      |> form("#participation-form",
        participation: %{
          email: "camille@example.org",
          name: "Camille",
          location: "h2x",
          newsletter: "true"
        }
      )
      |> render_submit()

      assert has_element?(view, "#account-email-pending")

      request =
        PauseAiCa.Repo.get_by!(PauseAiCa.Participation.Request, email: "camille@example.org")

      assert request.state == "pending"
      assert request.newsletter
      assert request.name == "Camille"
      assert request.fsa == "H2X"
      refute PauseAiCa.Newsletters.eligible?(request.email)
      refute PauseAiCa.Accounts.get_user_by_email(request.email)
    end

    test "invalid postal area keeps the bilingual form entries and sends nothing", %{conn: conn} do
      for path <- ["/en/learn", "/fr/comprendre"] do
        {:ok, view, _html} = live(conn, path)

        view
        |> form("#participation-form",
          participation: %{
            email: "invalid-area@example.org",
            name: "Camille",
            location: "123",
            newsletter: "true"
          }
        )
        |> render_submit()

        assert has_element?(view, "#participation-validation")
        assert has_element?(view, "input[name='participation[name]'][value='Camille']")

        assert has_element?(
                 view,
                 "input[name='participation[email]'][value='invalid-area@example.org']"
               )

        assert has_element?(view, "input[name='participation[location]'][value='123']")
        assert has_element?(view, "#participation_newsletter[checked]")

        refute PauseAiCa.Repo.get_by(PauseAiCa.Newsletters.Subscription,
                 email: "invalid-area@example.org"
               )

        refute_receive {:email, _}
      end
    end

    test "LEARN-REQ-08 anonymous local follow-up is an explicit request without an account", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/fr/participer?intent=waitlist")
      before = PauseAiCa.Repo.aggregate(PauseAiCa.Accounts.User, :count)

      view
      |> form("#participation-form",
        participation: %{email: "local@example.org", location: "H2X"}
      )
      |> render_submit()

      assert has_element?(view, "#account-email-pending")
      assert PauseAiCa.Repo.aggregate(PauseAiCa.Accounts.User, :count) == before
      assert_receive {:email, _}
      refute PauseAiCa.Repo.exists?(PauseAiCa.Newsletters.Subscription)
    end

    test "LEARN-REQ-08 invalid local input preserves the task", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/en/participate?intent=waitlist")

      view
      |> form("#participation-form",
        participation: %{email: "local@example.org", location: "123"}
      )
      |> render_submit()

      assert has_element?(view, "#participation-form input[value='123']")
      refute has_element?(view, "#account-email-pending")
      refute_receive {:email, _}
    end

    test "nothing is sent without consent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      view
      |> form("#participation-form", participation: %{email: "camille@example.org"})
      |> render_submit()

      assert has_element?(view, "#participation-validation")
      refute has_element?(view, "#account-email-pending")
    end

    test "an address already on the list gets the same friendly answer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fr/comprendre")

      view
      |> form("#participation-form",
        participation: %{email: "taken@example.org", location: "H2X", newsletter: "true"}
      )
      |> render_submit()

      assert has_element?(view, "#account-email-pending")
    end

    test "a bad address is explained rather than swallowed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/learn")

      view
      |> form("#participation-form", participation: %{email: "nope", newsletter: "true"})
      |> render_submit()

      assert has_element?(view, "#participation-validation")
    end
  end
end
