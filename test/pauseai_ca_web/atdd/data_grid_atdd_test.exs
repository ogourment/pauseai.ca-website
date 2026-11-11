if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.DataGridTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, CRM, ContactLists, Repo}
    alias PauseAiCaWeb.{AtddEvidence, AtddNavigation}
    @moduletag :atdd
    @scenarios for locale <- ["en", "fr"],
                   do: %{
                     id: "CRM-GRID-01-#{locale}",
                     title: "Filter, select and email through shared grid",
                     roles: ["Superadmin"],
                     language: locale,
                     device: if(locale == "fr", do: "Phone", else: "Desktop"),
                     source_file: __ENV__.file
                   }
    setup_all do
      previous = Application.get_env(:pauseai_ca, :data_grid_enabled)
      Application.put_env(:pauseai_ca, :data_grid_enabled, true)

      AtddEvidence.reset!("CRM-GRID-01 · server-backed contacts and lists", @scenarios, %{
        browser: "Chromium",
        viewport: "English desktop / French phone"
      })

      on_exit(fn ->
        AtddEvidence.finalize!()

        if is_nil(previous),
          do: Application.delete_env(:pauseai_ca, :data_grid_enabled),
          else: Application.put_env(:pauseai_ca, :data_grid_enabled, previous)
      end)

      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-GRID-01 filters real server data and reuses existing actions #{locale}", c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      scope = Accounts.Scope.for_user(admin)

      for {name, city} <- [
            {"Avery Vancouver", "Vancouver"},
            {"Morgan Vancouver", "Vancouver"},
            {"Blair Ottawa", "Ottawa"}
          ] do
        {:ok, _} =
          CRM.create(scope, %{
            name: name,
            city: city,
            email: "#{String.downcase(String.first(name))}-#{locale}@example.org"
          })
      end

      {:ok, list} =
        ContactLists.save(scope, nil, %{
          "name" => "Vancouver grid #{locale}",
          "kind" => "dynamic",
          "city" => "Vancouver"
        })

      {token, _} = generate_user_magic_link_token(admin)

      browser =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_has("#account-menu")
        |> visit("/#{locale}")
        |> AtddNavigation.open_section("manage")
        |> click_link(
          "#manage-menu [data-navigation-item='pauseai.contacts']",
          tr(locale, "Contacts"),
          exact: true
        )
        |> assert_has("#crm-grid .tabulator-row", count: 3)
        |> watch_grid_errors()
        |> capture(
          locale,
          1,
          "Open Contacts from Manage",
          "Public home page",
          "Manage → Contacts"
        )
        |> fill_in(
          "#crm-grid [tabulator-field='city'] input",
          tr(locale, "City") <> " " <> tr(locale, "filter"),
          with: "Vancouver"
        )
        |> assert_has("#crm-grid .tabulator-row", count: 2)
        |> PhoenixTest.Playwright.click("#crm-grid .data-grid-select-all")
        |> assert_has("#crm-selection-actions",
          text: tr(locale, "%{count} selected across pages", count: 2)
        )
        |> capture(
          locale,
          2,
          "Vancouver filter and selected recipients",
          "Contacts",
          "City filter → Vancouver → Select this page"
        )
        # Changing this host setting patches both grid config and revision.
        # The checked audience must survive while the replacement table builds.
        |> PhoenixTest.Playwright.click("#crm-geography-options > summary")
        |> select("#crm-per", tr(locale, "Rows per page"), option: "10", exact: false)
        |> assert_has("#crm-grid[data-grid-revision='2']")
        |> assert_has("#crm-grid .tabulator-row", count: 2)
        |> assert_has("#crm-selection-actions",
          text: tr(locale, "%{count} selected across pages", count: 2)
        )
        |> assert_no_grid_errors()
        |> click_button("#crm-email-selected", tr(locale, "Email"), exact: true)
        |> assert_has("#newsletter-draft-form")

      assert {:ok, [draft]} = PauseAiCa.Newsletters.Drafts.list(scope)
      assert length(draft.recipient_keys) == 2
      assert Repo.aggregate(PauseAiCa.Newsletters.Delivery, :count) == 0

      browser =
        browser
        |> AtddNavigation.open_section("manage")
        |> click_link(
          "#manage-menu [data-navigation-item='pauseai.contact_lists']",
          tr(locale, "Lists"),
          exact: true
        )
        |> assert_has("#lists-grid .tabulator-row", count: 1)
        |> assert_has("#lists-grid .tabulator-row", text: tr(locale, "Dynamic"))
        |> capture(
          locale,
          3,
          "Saved dynamic list uses the same grid",
          "Email draft",
          "Manage → Lists"
        )
        |> PhoenixTest.Playwright.click("#lists-grid .data-grid-row-checkbox")
        |> click_button("button", tr(locale, "Edit"), exact: true)
        |> assert_has("#selected-contact-list", text: list.name)

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "CRM-GRID-01-#{locale}"))
      )

      browser
    end

    defp watch_grid_errors(browser) do
      PhoenixTest.Playwright.evaluate(browser, """
      (() => {
        window.__crmGridErrors = [];
        const original = console.error.bind(console);
        console.error = (...values) => {
          window.__crmGridErrors.push(values.map(String).join(' '));
          original(...values);
        };
      })()
      """)
    end

    defp assert_no_grid_errors(browser) do
      PhoenixTest.Playwright.evaluate(browser, "window.__crmGridErrors", &assert(&1 == []))
    end

    defp capture(browser, locale, step, title, preceding, control) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:grid_capture_url, &1)
      )

      url = AtddEvidence.safe_url(Process.get(:grid_capture_url))
      IO.puts("Capture URL: #{url}")
      filename = "CRM-GRID-01-#{locale}-#{step}.png"

      PhoenixTest.Playwright.evaluate(
        browser,
        "({html:document.documentElement.outerHTML,url:location.href,values:[...document.querySelectorAll('input,select,textarea')].map(el=>({value:el.value,checked:el.checked}))})",
        fn capture ->
          capture = Map.update!(capture, "html", &AtddEvidence.scrub_html/1)

          File.write!(
            Path.join("tmp/atdd/screenshots", filename <> ".raw.json"),
            Jason.encode!(capture)
          )
        end
      )

      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        title,
        "Synthetic authorized records; no provider send.",
        %{
          "scenario_id" => "CRM-GRID-01-#{locale}",
          "url" => url,
          "preceding_screen" => preceding,
          "control" => control,
          "step" => step,
          "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser))
        }
      )

      browser
    end

    defp tr(locale, text, bindings \\ []),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text, bindings)
        end)
  end
end
