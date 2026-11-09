if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.PublicGroupsEventsTest do
    use AcceptanceHarness.Playwright.Case, async: false

    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Incubators, Newsletters, Participation, Repo, Volunteers, Welcome}
    alias PauseAiCaWeb.{AtddEvidence, AtddNavigation}

    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "PUBLIC-GROUPS-EVENTS-01-#{locale}",
                    title: "Public groups, upcoming events and local interest · #{language}",
                    tags: ["incubators", "participation", "events"],
                    roles: ["Interested visitor"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("PUBLIC-GROUPS-EVENTS-01 · configured public directory", @scenarios, %{
        browser: "Chromium",
        viewport: "English 1280 × 900; French 390 × 844"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      previous = Application.get_env(:swoosh, :shared_test_process)
      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.put_env(:swoosh, :shared_test_process, previous) end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "PUBLIC-GROUPS-EVENTS-01 configured directory #{locale}", c do
        locale = unquote(locale)
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        groups = configured_groups()
        discard_fixture_emails()
        baseline = counts()
        directory = if locale == "fr", do: "/fr/groupes", else: "/en/groups"
        help_control = "#group-#{groups.toronto.id} button[phx-value-kind='help']"
        waitlist_control = "#group-#{groups.ottawa.id} button[phx-click='choose-group']"

        # The public home is static. Only wait for LiveView after entering Groups.
        b =
          c.conn
          |> visit("/#{locale}")
          |> AtddNavigation.open_public()
          |> capture(
            locale,
            "Public home with Get involved menu open",
            "Open Get involved",
            "Click #act-local-groups"
          )
          |> click_link("#act-local-groups", tr(locale, "Local groups"), exact: true)
          |> assert_path(directory)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#participation-form")

        PhoenixTest.Playwright.evaluate(
          b,
          "document.querySelectorAll('#incubators article[id^=group-]').length === 3",
          &assert(&1)
        )

        for group <- [groups.montreal, groups.toronto, groups.ottawa] do
          b |> assert_has("#group-#{group.id} h2", text: group.name)
        end

        b
        |> assert_has("#group-#{groups.montreal.id} a[href*='/join?']",
          text: tr(locale, "Request to join")
        )
        |> refute_has("#group-#{groups.toronto.id} a[href*='/join?']")
        |> refute_has("#group-#{groups.ottawa.id} a[href*='/join?']")
        |> assert_has(help_control, text: tr(locale, "I can help"))
        |> assert_has(waitlist_control, text: tr(locale, "Join the waitlist"))
        |> refute_has("#group-next-event-#{groups.ottawa.id}")

        for group <- [groups.montreal, groups.toronto] do
          b
          |> assert_has("#group-#{group.id} a[href='#{group.events_url}']",
            text: tr(locale, "Group events")
          )
          |> assert_has("#group-next-event-#{group.id} a[href='#{group.event_url}']",
            text: event_title(locale)
          )
          |> assert_has("#group-next-event-#{group.id} time",
            text: Welcome.display_time(groups.starts_at, "America/Toronto")
          )

          PhoenixTest.Playwright.evaluate(
            b,
            """
            (() => {
              const card = document.getElementById('group-#{group.id}');
              const events = card.querySelector('a[href="#{group.events_url}"]');
              const next = document.getElementById('group-next-event-#{group.id}');
              const time = next.querySelector('time');
              return !!(events.compareDocumentPosition(next) & Node.DOCUMENT_POSITION_FOLLOWING)
                && next.getBoundingClientRect().top >= events.getBoundingClientRect().bottom
                && Date.parse(time.dateTime) > Date.now();
            })()
            """,
            &assert(&1)
          )
        end

        b =
          b
          |> capture(
            locale,
            "Configured public directory",
            "Click #act-local-groups",
            "Three cards; two upcoming events below Group events"
          )
          |> fill_in(tr(locale, "Name"), with: "Morgan Synthetic")
          |> fill_in(tr(locale, "Your email"), with: "groups-demo-#{locale}@example.org")
          |> fill_in(tr(locale, "FSA"), with: "H2X")
          |> click_button(help_control, tr(locale, "I can help"), exact: true)
          |> assert_has("#participation-selected-group",
            text: tr_group(locale, :help, groups.toronto.name)
          )
          |> assert_local_kind("help")
          |> assert_has("textarea[name='participation[help_text]']")
          |> assert_person_details(locale)
          |> capture(
            locale,
            "Toronto help selected",
            "Click #{help_control}",
            "Toronto selected with help intent; personal details retained"
          )
          |> click_button(waitlist_control, tr(locale, "Join the waitlist"), exact: true)
          |> assert_has("#participation-selected-group",
            text: tr_group(locale, :waitlist, groups.ottawa.name)
          )
          |> assert_local_kind("waitlist")
          |> refute_has("textarea[name='participation[help_text]']")
          |> assert_person_details(locale)
          |> capture(
            locale,
            "Ottawa waitlist selected",
            "Click #{waitlist_control}",
            "Ottawa selected with waitlist intent; no submission"
          )

        assert counts() == baseline
        refute_receive {:email, _}
        assert b

        AtddEvidence.mark_scenario_success!(
          Enum.find(@scenarios, &(&1.id == "PUBLIC-GROUPS-EVENTS-01-#{locale}"))
        )
      end
    end

    defp configured_groups do
      admin =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()
        |> Accounts.Scope.for_user()

      date = Date.utc_today() |> Date.add(30) |> Date.to_iso8601()
      {:ok, starts_at} = Welcome.local_time(date <> "T13:30", "America/Toronto")

      profiles =
        for {key, name, stage, event?} <- [
              {:montreal, "Montréal", "active", true},
              {:toronto, "Toronto", "incubator", true},
              {:ottawa, "Ottawa", "incubator", false}
            ],
            into: %{} do
          {:ok, group} = Volunteers.create_group(admin, %{name: name})
          events_url = "https://example.org/synthetic-#{key}/calendar"
          event_url = "https://example.org/synthetic-#{key}/next"

          attrs = %{
            name_en: name,
            name_fr: name,
            published: true,
            stage: stage,
            events_url: events_url
          }

          attrs =
            if event?,
              do:
                Map.merge(attrs, %{
                  next_event_title_en: event_title("en"),
                  next_event_title_fr: event_title("fr"),
                  next_event_starts_at: starts_at,
                  next_event_timezone: "America/Toronto",
                  next_event_url: event_url
                }),
              else: attrs

          {:ok, _} = Incubators.configure(admin, group.id, attrs)
          {key, %{id: group.id, name: name, events_url: events_url, event_url: event_url}}
        end

      Map.put(profiles, :starts_at, starts_at)
    end

    defp event_title("fr"), do: "Rencontre fictive à venir"
    defp event_title(_), do: "Synthetic upcoming gathering"

    defp assert_local_kind(b, kind) do
      # The visible selected-group caption above waits for the server patch.
      # The submitted intent is a hidden input, so inspect its DOM value directly.
      PhoenixTest.Playwright.evaluate(
        b,
        """
        (() => {
          const fields = document.querySelectorAll('#participation-form input[name="participation[local_kind]"]');
          return fields.length === 1 && fields[0].type === 'hidden' && fields[0].value === #{Jason.encode!(kind)};
        })()
        """,
        &assert(&1)
      )

      b
    end

    defp assert_person_details(b, locale) do
      PhoenixTest.Playwright.evaluate(
        b,
        """
        document.querySelector('[name="participation[name]"]').value === 'Morgan Synthetic'
          && document.querySelector('#participation_email').value === 'groups-demo-#{locale}@example.org'
          && document.querySelector('[name="participation[location]"]').value === 'H2X'
        """,
        &assert(&1)
      )

      b
    end

    # Fixture account confirmation precedes the measured public browsing journey.
    defp discard_fixture_emails do
      receive do
        {:email, _} -> discard_fixture_emails()
      after
        0 -> :ok
      end
    end

    defp counts,
      do: %{
        accounts: Repo.aggregate(Accounts.User, :count),
        subscriptions: Repo.aggregate(Newsletters.Subscription, :count),
        memberships: Repo.aggregate(Incubators.Membership, :count),
        managers: Repo.aggregate(Volunteers.Manager, :count),
        requests: Repo.aggregate(Participation.Request, :count),
        deliveries: Repo.aggregate(Newsletters.Delivery, :count)
      }

    defp tr_group(locale, kind, group) do
      Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
        case kind do
          :help ->
            Gettext.gettext(PauseAiCaWeb.Gettext, "Offer to help %{group}", group: group)

          :waitlist ->
            Gettext.gettext(PauseAiCaWeb.Gettext, "Waitlist for %{group}", group: group)
        end
      end)
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

      sid = "PUBLIC-GROUPS-EVENTS-01-#{locale}"
      step = Process.get({:public_groups_step, sid}, 0) + 1
      Process.put({:public_groups_step, sid}, step)
      name = "#{sid}-#{step}.png"
      PhoenixTest.Playwright.evaluate(b, "location.href", &Process.put(:public_groups_url, &1))

      metadata = %{
        "scenario_id" => sid,
        "url" => AtddEvidence.safe_url(Process.get(:public_groups_url)),
        "control" => control,
        "screen" => screen,
        "preceding_screen" => Process.get({:public_groups_screen, sid}, "Public home"),
        "source" =>
          "Actual local synthetic directory; example.org event links; no submission or external event fetch"
      }

      AcceptanceHarness.Evidence.record_pending_step(name, control, outcome, metadata)
      b = AtddEvidence.capture_full_page(b, name)

      AtddEvidence.record_step(
        name,
        control,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(b)))
      )

      Process.put({:public_groups_screen, sid}, screen)
      b
    end
  end
end
