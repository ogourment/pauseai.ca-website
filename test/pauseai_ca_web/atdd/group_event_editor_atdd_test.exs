if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.GroupEventEditorTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Incubators, Repo, Volunteers, Welcome}
    alias PauseAiCaWeb.{AtddEvidence, AtddNavigation}

    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "GROUP-EVENT-EDITOR-01-#{locale}",
                    title: "Configure next group event · #{language}",
                    tags: ["incubators", "events", "forms"],
                    roles: ["Superadmin"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("GROUP-EVENT-EDITOR-01 · persistent event disclosure", @scenarios, %{
        browser: "Chromium",
        viewport: "English desktop and French phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "GROUP-EVENT-EDITOR-01 edit, reload and publish #{locale}", c do
        locale = unquote(locale)
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        scope = Accounts.Scope.for_user(admin)
        {:ok, group} = Volunteers.create_group(scope, %{name: "Synthetic event editor group"})

        {:ok, _} =
          Incubators.configure(scope, group.id, %{
            name_en: "Synthetic event editor group",
            name_fr: "Groupe fictif pour les événements",
            published: true
          })

        {token, _} = generate_user_magic_link_token(admin)
        date = Date.utc_today() |> Date.add(30) |> Date.to_iso8601()
        local_start = date <> "T13:30"
        {:ok, starts_at} = Welcome.local_time(local_start, "America/Toronto")
        path = "/manage/groups?" <> URI.encode_query(%{group: group.id, locale: locale})
        event_path = path <> "&section=next-event"
        title_en = "Synthetic next gathering"
        title_fr = "Prochaine rencontre fictive"
        event_url = "https://example.org/synthetic-event-editor"

        b =
          c.conn
          |> visit("/users/log-in/#{token}")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> assert_has("#account-menu")
          |> visit("/#{locale}")
          |> AtddNavigation.open_section("manage")
          |> capture(locale, "Management menu", "Open Management menu", "Click Local groups")
          |> click_link(
            "#manage-menu [data-navigation-item='pauseai.groups']",
            tr(locale, "Local groups"),
            exact: true
          )
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#incubator-config")
          |> PhoenixTest.Playwright.click("#incubator-next-event summary")
          |> assert_path("/manage/groups",
            query_params: %{group: group.id, locale: locale, section: "next-event"}
          )
          |> assert_has("#incubator-next-event[open]")
          |> capture(
            locale,
            "Next group event open",
            "Click #incubator-next-event summary",
            "Enter every field sequentially"
          )
          |> fill_in(tr(locale, "English event title"), with: title_en)
          |> assert_has("#incubator-next-event[open] input[name='profile[next_event_title_en]']",
            value: title_en
          )
          |> fill_in(tr(locale, "French event title"), with: title_fr)
          |> assert_has("#incubator-next-event[open] input[name='profile[next_event_title_fr]']",
            value: title_fr
          )
          |> fill_in(tr(locale, "Event date and local time"), with: local_start)
          |> assert_has(
            "#incubator-next-event[open] input[name='profile[next_event_local_start]']",
            value: local_start
          )
          |> fill_in(tr(locale, "Event time zone"), with: "America/Toronto")
          |> assert_has("#incubator-next-event[open] input[name='profile[next_event_timezone]']",
            value: "America/Toronto"
          )
          |> fill_in(tr(locale, "Event link"), with: event_url)
          |> assert_has("#incubator-next-event[open] input[name='profile[next_event_url]']",
            value: event_url
          )
          |> click_button(tr(locale, "Save configuration"))
          |> assert_has("#flash-info", text: tr(locale, "Group configuration saved."))
          |> visit(event_path)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#incubator-next-event[open] input[name='profile[next_event_title_en]']",
            value: title_en
          )
          |> assert_has("#incubator-next-event input[name='profile[next_event_title_fr]']",
            value: title_fr
          )
          |> assert_has("#incubator-next-event input[name='profile[next_event_local_start]']",
            value: local_start
          )
          |> assert_has("#incubator-next-event input[name='profile[next_event_timezone]']",
            value: "America/Toronto"
          )
          |> assert_has("#incubator-next-event input[name='profile[next_event_url]']",
            value: event_url
          )
          |> capture(
            locale,
            "Saved event after full reload",
            "Click Save configuration, then reload the section URL",
            "All five values retained and event editor remains open"
          )
          |> AtddNavigation.open_public()
          |> click_link("#act-local-groups", tr(locale, "Local groups"), exact: true)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#group-next-event-#{group.id} a[href='#{event_url}']",
            text: if(locale == "fr", do: title_fr, else: title_en)
          )
          |> assert_has("#group-next-event-#{group.id} time",
            text: Welcome.display_time(starts_at, "America/Toronto")
          )
          |> capture(
            locale,
            "Public next event",
            "Open public menu and click #act-local-groups",
            "Localized event title, local time and event link visible"
          )

        assert {:ok, profile} = Incubators.configuration(scope, group.id)
        assert DateTime.compare(profile.next_event_starts_at, starts_at) == :eq
        assert profile.next_event_title_en == title_en
        assert profile.next_event_title_fr == title_fr
        assert profile.next_event_url == event_url
        assert b

        AtddEvidence.mark_scenario_success!(
          Enum.find(@scenarios, &(&1.id == "GROUP-EVENT-EDITOR-01-#{locale}"))
        )
      end
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(b, locale, screen, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        b,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      sid = "GROUP-EVENT-EDITOR-01-#{locale}"
      step = Process.get({:group_event_step, sid}, 0) + 1
      Process.put({:group_event_step, sid}, step)
      filename = "#{sid}-#{step}.png"
      PhoenixTest.Playwright.evaluate(b, "location.href", &Process.put(:group_event_url, &1))

      metadata = %{
        "scenario_id" => sid,
        "url" => AtddEvidence.safe_url(Process.get(:group_event_url)),
        "control" => control,
        "screen" => screen,
        "preceding_screen" => Process.get({:group_event_screen, sid}, "Signed-in public home"),
        "source" =>
          "Actual local synthetic group editor; example.org event link; no external event fetch"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, control, outcome, metadata)
      b = AtddEvidence.capture_full_page(b, filename)

      AtddEvidence.record_step(
        filename,
        control,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(b)))
      )

      Process.put({:group_event_screen, sid}, screen)
      b
    end
  end
end
