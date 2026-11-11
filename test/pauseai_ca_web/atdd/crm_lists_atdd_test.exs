if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.CRMListsTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, ContactLists, CRM, Newsletters, Repo}
    alias PauseAiCaWeb.{AtddEvidence, AtddNavigation}

    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "CRM-UX-LISTS-01-#{locale}",
                     title: "Static and dynamic contact lists · #{language}",
                     roles: ["Superadmin"],
                     language: language,
                     device: device,
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!("CRM-UX-LISTS-01 · contact collections and one composer", @scenarios, %{
        browser: "Chromium",
        viewport: "English desktop and French phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-UX-LISTS-01 creates lists, adds selected contacts and opens a newsletter draft #{locale}",
           c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      scope = Accounts.Scope.for_user(admin)

      {:ok, first} =
        CRM.create(scope, %{
          name: "Avery Vancouver",
          city: "Vancouver",
          email: "avery-#{locale}@example.org"
        })

      {:ok, second} =
        CRM.create(scope, %{
          name: "Morgan Vancouver",
          city: "Vancouver",
          email: "morgan-#{locale}@example.org"
        })

      {:ok, outside} =
        CRM.create(scope, %{
          name: "Riley Burnaby",
          city: "Burnaby",
          email: "riley-#{locale}@example.org"
        })

      for email <- ["avery-#{locale}@example.org", "morgan-#{locale}@example.org"] do
        Repo.insert!(%Newsletters.Subscription{
          email: email,
          city: "Vancouver",
          state: "confirmed",
          consent_version: "synthetic-list-review",
          confirmed_at: DateTime.utc_now()
        })
      end

      baseline_users = Repo.aggregate(Accounts.User, :count)
      {token, _} = generate_user_magic_link_token(admin)
      flush_emails()
      static_name = "Vancouver volunteers #{locale}"

      browser =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> assert_has("#account-menu")
        |> visit("/#{locale}")
        |> assert_has("#account-menu")
        |> open_lists(locale)
        |> click_button(tr(locale, "New list"))
        |> select("#list_kind", tr(locale, "Type"), option: tr(locale, "Static"), exact: false)
        |> fill_in("#list_name", tr(locale, "Name"), with: static_name)
        |> click_button("#contact-list-save", tr(locale, "Save list"), exact: true)
        |> assert_has("#selected-contact-list", text: static_name)
        |> assert_has("#selected-contact-list",
          text: tr(locale, "%{count} matching contacts", count: 0)
        )

      list = Repo.get_by!(PhoenixCRM.MailingList, name: static_name)
      assert list.criteria == %{"kind" => "static", "person_ids" => []}

      browser =
        browser
        |> AtddNavigation.open_section("manage")
        |> click_link(
          "#manage-menu [data-navigation-item='pauseai.contacts']",
          tr(locale, "Contacts"),
          exact: true
        )
        |> assert_has("[data-phx-main].phx-connected")
        |> PhoenixTest.Playwright.click("#crm-select-#{first.person.id}")
        |> assert_has("#crm-select-#{first.person.id}:checked")
        |> PhoenixTest.Playwright.click("#crm-select-#{second.person.id}")
        |> assert_has("#crm-select-#{second.person.id}:checked")
        |> click_button("#crm-list-selected", tr(locale, "Add to list"), exact: true)
        |> select("#crm-add-to-list select", tr(locale, "List"),
          option: static_name,
          exact: false
        )
        |> click_button("#crm-add-to-list button", tr(locale, "Add selected to list"),
          exact: true
        )
        |> refute_has("#crm-add-to-list")

      assert {:ok, saved} = ContactLists.get(scope, list.id)

      assert MapSet.new(saved.criteria["person_ids"]) ==
               MapSet.new([first.person.id, second.person.id])

      browser =
        browser
        |> open_lists(locale)
        |> click_link("#contact-list-#{list.id} a", static_name, exact: true)
        |> assert_has("#selected-contact-list",
          text: tr(locale, "%{count} matching contacts", count: 2)
        )
        |> click_link("#selected-contact-list a", tr(locale, "View contacts"), exact: true)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#crm-contact-#{first.person.id}")
        |> assert_has("#crm-contact-#{second.person.id}")
        |> refute_has("#crm-contact-#{outside.person.id}")
        |> capture(
          locale,
          1,
          "Static list contains the selected contacts",
          "Contacts directory",
          "Select Avery and Morgan → Add to list → Vancouver volunteers → View contacts",
          "Two existing canonical contacts belong to the saved static list. Burnaby is excluded and account/consent records retain their independent state."
        )
        |> open_lists(locale)
        |> click_link("#contact-list-#{list.id} a", static_name, exact: true)
        |> click_button("#contact-list-compose-newsletter", tr(locale, "Compose newsletter"),
          exact: true
        )
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#newsletter-draft-form")
        |> assert_has("#email-audience-summary",
          text:
            tr(locale, "%{list} · %{count} eligible · %{edition}",
              list: static_name,
              count: 2,
              edition: tr(locale, "Bilingual · language unknown only")
            ),
          exact: true
        )
        |> capture(
          locale,
          2,
          "The selected list opens the shared composer",
          "Static list",
          "Vancouver volunteers → Compose newsletter",
          "The actor-owned draft identifies the list, two eligible subscribers and the unknown-language bilingual edition. The workflow stops before preparation or sending."
        )

      assert {:ok, [draft]} = Newsletters.Drafts.list(scope)
      assert draft.owner_id == admin.id
      assert draft.mailing_list_id == list.id
      assert draft.recipient_mode == "list"

      dynamic_name = "Vancouver city #{locale}"

      browser =
        browser
        |> open_lists(locale)
        |> click_button(tr(locale, "New list"))
        |> select("#list_kind", tr(locale, "Type"), option: tr(locale, "Dynamic"), exact: false)
        |> fill_in("#list_name", tr(locale, "Name"), with: dynamic_name)
        |> fill_in(tr(locale, "Cities"), with: "Vancouver")
        |> click_button("#contact-list-save", tr(locale, "Save list"), exact: true)
        |> assert_has("#selected-contact-list", text: dynamic_name)
        |> assert_has("#selected-contact-list",
          text: tr(locale, "%{count} matching contacts", count: 2)
        )
        |> click_link("#selected-contact-list a", tr(locale, "View contacts"), exact: true)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#crm-contact-#{first.person.id}")
        |> assert_has("#crm-contact-#{second.person.id}")
        |> refute_has("#crm-contact-#{outside.person.id}")
        |> capture(
          locale,
          3,
          "Dynamic Vancouver city rule",
          "Lists workspace",
          "New list → Dynamic → Cities Vancouver → Save list → View contacts",
          "The saved recorded-city rule includes the two Vancouver contacts and excludes Burnaby. This fixture makes no postal-boundary claim."
        )

      assert Repo.aggregate(Accounts.User, :count) == baseline_users
      assert Repo.aggregate(Newsletters.Subscription, :count) == 2
      assert Repo.aggregate(Newsletters.Batch, :count) == 0
      assert Repo.aggregate(Newsletters.Delivery, :count) == 0
      refute_received {:email, _}

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "CRM-UX-LISTS-01-#{locale}"))
      )

      browser
    end

    defp open_lists(browser, locale) do
      browser
      |> AtddNavigation.open_section("manage")
      |> click_link(
        "#manage-menu [data-navigation-item='pauseai.contact_lists']",
        tr(locale, "Lists"),
        exact: true
      )
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#contact-lists")
    end

    defp capture(browser, locale, step, title, preceding, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      PhoenixTest.Playwright.evaluate(browser, "location.href", &Process.put(:crm_lists_url, &1))
      url = AtddEvidence.safe_url(Process.get(:crm_lists_url))
      IO.puts("Capture URL: #{url}")
      filename = "CRM-UX-LISTS-01-#{locale}-#{step}.png"
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(filename, title, outcome, %{
        "scenario_id" => "CRM-UX-LISTS-01-#{locale}",
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "step" => step,
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser)),
        "external_systems" =>
          "Isolated synthetic contacts, existing consent fixtures and private drafts. No provider calls or sending."
      })

      browser
    end

    defp flush_emails do
      receive do
        {:email, _} -> flush_emails()
      after
        0 -> :ok
      end
    end

    defp tr(locale, text, bindings \\ []),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text, bindings)
        end)
  end
end
