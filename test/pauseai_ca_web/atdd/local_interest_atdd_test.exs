if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.LocalInterestTest do
    use AcceptanceHarness.Playwright.Case, async: false

    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Repo}
    alias PauseAiCa.Participation.Request
    alias PauseAiCaWeb.{AtddEvidence, AtddNavigation}

    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "LOCAL-FOLLOWUP-01-#{locale}",
                    title: "Local request follow-up and shared gutters · #{language}",
                    tags: ["participation", "management", "layout"],
                    roles: ["Superadmin"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("LOCAL-FOLLOWUP-01 · organizer follow-up", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "LOCAL-FOLLOWUP-01 queue and contained page #{locale}", c do
        locale = unquote(locale)
        id = "LOCAL-FOLLOWUP-01-#{locale}"
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

        operator =
          user_fixture()
          |> Ecto.Changeset.change(superadmin: true, name: "Synthetic organizer")
          |> Repo.update!()

        now = DateTime.utc_now()

        request =
          Repo.insert!(%Request{
            email: "synthetic-request@example.org",
            name: "Synthetic local volunteer",
            locale: locale,
            state: "confirmed",
            local_kind: "waitlist",
            city: "Toronto",
            confirmed_at: now,
            expires_at: DateTime.add(now, 86_400),
            withdrawal_hash: :crypto.strong_rand_bytes(32)
          })

        {token, _} = generate_user_magic_link_token(operator)
        row = "#local-request-#{request.id}"

        browser =
          c.conn
          |> visit("/users/log-in/#{token}")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/#{locale}")
          |> AtddNavigation.open_section("admin")
          |> capture(
            id,
            "Administration menu",
            "/#{locale} · signed-in homepage",
            "Administration menu"
          )
          |> click_link(
            "#admin-menu [data-navigation-item='pauseai.local-interest']",
            tr(locale, "Local participation"),
            exact: true
          )
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has(row, text: tr(locale, "Requested to join a local group"))
          |> capture(
            id,
            "Confirmed local request",
            "/#{locale} · Administration menu",
            tr(locale, "Local participation")
          )
          |> click_button("#{row} button", tr(locale, "I’ll follow up"))
          |> assert_has(row,
            text: tr(locale, "Follow-up by %{organizer}", organizer: operator.name)
          )
          |> visit("/admin/local-interest?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has(row,
            text: tr(locale, "Follow-up by %{organizer}", organizer: operator.name)
          )
          |> capture(
            id,
            "Assigned organizer survives reload",
            "/admin/local-interest · confirmed request",
            "#{tr(locale, "I’ll follow up")} · reload"
          )

        assert Repo.reload!(request).followup_owner_id == operator.id
        assert is_nil(Repo.reload!(request).user_id)
        assert Repo.aggregate(Accounts.User, :count) == 1

        evaluate(
          browser,
          """
          (() => {
            const content = document.querySelector('.management-content');
            const heading = content.querySelector('h1').getBoundingClientRect();
            const crumbs = document.querySelector('.app-shell-breadcrumbs').getBoundingClientRect();
            return Math.abs(heading.left - crumbs.left) <= 1 && heading.left >= 19;
          })()
          """,
          &assert(&1)
        )

        browser =
          browser
          |> visit("/manage/administrators?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#administrators")
          |> capture(
            id,
            "Existing narrow administration page",
            "/admin/local-interest · assigned request",
            "Navigate directly to /manage/administrators?locale=#{locale}"
          )

        evaluate(
          browser,
          """
          (() => {
            const content = document.querySelector('.management-content');
            const page = document.querySelector('#administrators');
            const outer = getComputedStyle(content);
            const inner = getComputedStyle(page);
            return parseFloat(outer.paddingLeft) === 0 && parseFloat(inner.paddingLeft) === 20
              && page.getBoundingClientRect().width <= 1024;
          })()
          """,
          &assert(&1)
        )

        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      end
    end

    defp tr(locale, text, bindings \\ []),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text, bindings)
        end)

    defp capture(browser, id, title, preceding, control) do
      evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      step = Process.get({:local_followup_step, id}, 0) + 1
      Process.put({:local_followup_step, id}, step)
      filename = "#{id}-#{step}.png"
      evaluate(browser, "location.href", &Process.put(:local_followup_url, &1))
      url = AtddEvidence.safe_url(Process.get(:local_followup_url))
      IO.puts("Capture URL: #{url}")

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "fixture" => "Synthetic local organizer and request; no external messages"
      }

      outcome =
        "Clear request and organizer attribution, aligned shared gutters, preserved narrow page."

      AcceptanceHarness.Evidence.record_pending_step(filename, title, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        title,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
