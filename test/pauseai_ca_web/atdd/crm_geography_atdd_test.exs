if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.CRMGeographyTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{CRM, ContactMigration, Repo}
    alias PauseAiCa.Accounts.Scope
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "GEO-PAI-01-#{locale}",
                     title: "Current CRM geography and explicit area filters · #{language}",
                     roles: ["Superadmin"],
                     language: language,
                     device: device,
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!("GEO-PAI-01 · read-only geography filters", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "GEO-PAI-01 facets and canonical correction #{locale}", c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      fixture_address = admin.email
      # Registration is fixture setup; geography actions must emit no later mail.
      assert_received {:email, %Swoosh.Email{to: [{_, ^fixture_address}]}}
      refute_received {:email, _}
      scope = Scope.for_user(admin)

      {:ok, %{contacts: [legacy]}} =
        ContactMigration.import_selected(
          [
            %{
              "email" => "legacy-toronto@example.org",
              "name" => "Legacy Toronto",
              "city" => "Toronto",
              "sheet" => "Rest of Canada",
              "fsa" => "M5V"
            }
          ],
          "synthetic.csv",
          "geo-browser",
          admin
        )

      {:ok, legacy_record} = CRM.get_legacy(scope, legacy.id)

      {:ok, borough} =
        CRM.create(scope, %{
          email: "borough@example.org",
          name: "Toronto borough",
          city: "Scarborough"
        })

      {:ok, vancouver} =
        CRM.create(scope, %{
          email: "vancouver@example.org",
          name: "Vancouver city",
          city: "Vancouver"
        })

      {:ok, burnaby} =
        CRM.observe(
          scope,
          %{
            email: "burnaby@example.org",
            name: "Burnaby outside Vancouver",
            city: "Burnaby",
            province: "BC"
          },
          "synthetic",
          "burnaby"
        )

      {:ok, unknown} =
        CRM.observe(
          scope,
          %{email: "unknown@example.org", name: "Unknown place", region: "ROCanada"},
          "synthetic",
          "unknown"
        )

      source_before = Repo.get!(ContactMigration.Contact, legacy.id).source_data

      baseline =
        {Repo.aggregate(PauseAiCa.Accounts.User, :count),
         Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count)}

      {token, _} = generate_user_magic_link_token(admin)

      b =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/admin/contacts?locale=#{locale}")
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#crm-pagination", text: "5", exact: false)
        |> capture(
          locale,
          "Contacts before filtering",
          "Select Ontario in Provinces and territories; all five contacts are synthetic."
        )
        |> select("#crm-provinces", tr(locale, "Provinces and territories"),
          option: "Ontario",
          exact: false
        )
        |> assert_has("#crm-contact-#{legacy_record.person.id}")
        |> assert_has("#crm-contact-#{borough.person.id}")
        |> refute_has("#crm-contact-#{vancouver.person.id}")
        |> select("#crm-cities", tr(locale, "Cities"), option: "Toronto", exact: false)
        |> click_button(tr(locale, "Select this page"))
        |> assert_has("#crm-selection-actions",
          text: tr(locale, "%{count} selected across pages", count: 2),
          exact: false
        )
        |> capture(
          locale,
          "Ontario and Toronto overlap once",
          "Select this page selects exactly the same two canonical contacts as the OR filters."
        )

      {:ok, all} =
        CRM.directory_page(scope, %{
          "provinces" => ["ON"],
          "cities" => ["Toronto"],
          :all_rows => true
        })

      assert MapSet.new(Enum.map(all.records, & &1.person.id)) ==
               MapSet.new([legacy_record.person.id, borough.person.id])

      b =
        b
        |> select("#crm-provinces", tr(locale, "Provinces and territories"),
          option: [],
          exact: false
        )
        |> select("#crm-cities", tr(locale, "Cities"), option: "Vancouver", exact: false)
        |> assert_has("#crm-contact-#{vancouver.person.id}")
        |> refute_has("#crm-contact-#{burnaby.person.id}")
        |> assert_has("#crm-selection-actions",
          text: tr(locale, "%{count} selected across pages", count: 0),
          exact: false
        )
        |> capture(
          locale,
          "Vancouver means the city",
          "Changing geographic filters clears the prior selection; Burnaby does not match Vancouver."
        )
        |> select("#crm-cities", tr(locale, "Cities"), option: [], exact: false)
        |> fill_in(tr(locale, "FSA (first three postal-code characters)"), with: "m5v")
        |> assert_has("#crm-contact-#{legacy_record.person.id}")
        |> refute_has("#crm-contact-#{borough.person.id}")
        |> capture(
          locale,
          "Recorded FSA match",
          "The FSA field explains the first three postal-code characters. Only the recorded M5V matches."
        )
        |> fill_in(tr(locale, "FSA (first three postal-code characters)"), with: "")
        |> check(tr(locale, "Include contacts without a city, province or FSA"))
        |> assert_has("#crm-contact-#{unknown.person.id}")
        |> refute_has("#crm-contact-#{legacy_record.person.id}")
        |> capture(
          locale,
          "Unknown stays explicit",
          "The broad Rest of Canada observation does not imply Ontario or a city."
        )
        |> uncheck(tr(locale, "Include contacts without a city, province or FSA"))
        |> click_link("#crm-directory a", "Legacy Toronto", exact: true)
        |> assert_has("[data-phx-main].phx-connected")
        |> fill_in(tr(locale, "City"), with: "Vancouver", exact: true)
        |> click_button(tr(locale, "Save contact"))
        |> assert_has("[role='status']", text: tr(locale, "Saved"), exact: true)
        |> assert_has("#crm-contact-form [name='contact[city]']", value: "Vancouver")
        |> click_link(tr(locale, "Back to contacts"))
        |> assert_has("[data-phx-main].phx-connected")
        |> select("#crm-cities", tr(locale, "Cities"), option: "Vancouver", exact: false)
        |> assert_has("#crm-pagination",
          text:
            tr(locale, "Page %{page} of %{pages} · %{total} contacts",
              page: 1,
              pages: 1,
              total: 2
            ),
          exact: false
        )
        |> assert_has("#crm-contact-#{legacy_record.person.id}")
        |> assert_has("#crm-geography-#{legacy_record.person.id}",
          text: "Vancouver",
          exact: false
        )
        |> capture(
          locale,
          "Corrected city with preserved source history",
          "Save contact changes the canonical city; the old Toronto source remains visible as source evidence."
        )

      assert Repo.get!(ContactMigration.Contact, legacy.id).source_data == source_before
      assert {:ok, %{total: 1}} = CRM.directory_page(scope, %{"provinces" => ["ON"]})
      assert {:ok, %{total: 2}} = CRM.directory_page(scope, %{"cities" => ["Vancouver"]})

      assert baseline ==
               {Repo.aggregate(PauseAiCa.Accounts.User, :count),
                Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count)}

      refute_received {:email, _}

      PhoenixTest.Playwright.evaluate(
        b,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "GEO-PAI-01-#{locale}"))
      )

      b
    end

    defp tr(locale, text, bindings \\ []),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text, bindings)
        end)

    defp capture(browser, locale, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      step = Process.get({:geo_step, locale}, 0) + 1
      Process.put({:geo_step, locale}, step)
      filename = "GEO-PAI-01-#{locale}-#{step}.png"

      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:geo_capture_url, &1)
      )

      url = AtddEvidence.safe_url(Process.get(:geo_capture_url))
      IO.puts("Capture URL: #{url}")
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(filename, control, outcome, %{
        "scenario_id" => "GEO-PAI-01-#{locale}",
        "url" => url,
        "control" => control,
        "step" => step,
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser)),
        "external_systems" =>
          "Synthetic isolated database only; no newsletter list changes, provider writes or sending"
      })

      browser
    end
  end
end
