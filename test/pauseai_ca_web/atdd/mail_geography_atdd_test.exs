if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.MailGeographyTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, CRM, ContactMigration, Newsletters, Repo}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "MAIL-GEO-01-#{locale}",
                     title: "Contact geography and exact reviewed CSV · #{language}",
                     roles: ["Superadmin"],
                     language: language,
                     device: device,
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!(
        "MAIL-GEO-01 · composer geography and reviewed recipients",
        @scenarios,
        %{browser: "Chromium", viewport: "Desktop and phone"}
      )

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "MAIL-GEO-01 separates text and location and exports the reviewed snapshot #{locale}",
           c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      actor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      scope = Accounts.Scope.for_user(actor)

      {:ok, toronto} =
        CRM.create(scope, %{
          email: "toronto@example.org",
          name: "Toronto contact",
          city: "Toronto"
        })

      {:ok, gta} =
        CRM.create(scope, %{
          email: "mississauga@example.org",
          name: "Mississauga contact",
          city: "Mississauga"
        })

      {:ok, %{contacts: [legacy]}} =
        ContactMigration.import_selected(
          [
            %{
              "email" => "burnaby@example.org",
              "name" => "Burnaby contact",
              "city" => "Burnaby",
              "province" => "BC",
              "sheet" => "Rest of Canada",
              "source_observation" => %{"user" => %{"timezone" => "America/Toronto"}}
            }
          ],
          "synthetic.csv",
          "mail-geo",
          actor
        )

      {:ok, bc} = CRM.get_legacy(scope, legacy.id)
      sources_before = Repo.get!(ContactMigration.Contact, legacy.id).source_data

      {:ok, _saved_filter} =
        Newsletters.Lists.save(scope, nil, %{
          "name" => "Custom GTA review",
          "city" => "Toronto, Mississauga",
          "fsas" => "M5V"
        })

      {:ok, draft} = Newsletters.Drafts.create(scope)

      {:ok, draft} =
        Newsletters.Drafts.save(scope, draft, %{
          "subject" => "Synthetic local invitation",
          "source" => "An isolated review message.",
          "recipient_mode" => "contacts",
          "region" => "ROCanada"
        })

      path = "/manage/mail/drafts/#{draft.id}?locale=#{locale}"
      {token, _} = generate_user_magic_link_token(actor)
      flush_emails()

      b =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit(path)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#email-recipient-settings[open]")
        |> fill_in(tr(locale, "Search contact text"), with: "Toronto")
        |> assert_has("#newsletter-recipient-#{bc.person.id}")
        |> capture(
          locale,
          "Broad source text search",
          "Contacts picker",
          "Search contact text → Toronto",
          "The Burnaby source contains America/Toronto. This text result does not establish Toronto geography."
        )
        |> select("#mail-geography-areas", tr(locale, "Named areas"),
          option: "Toronto / GTA",
          exact: false
        )
        |> refute_has("#newsletter-recipient-#{bc.person.id}")
        |> fill_in(tr(locale, "Search contact text"), with: "")
        |> assert_has("#newsletter-recipient-#{toronto.person.id}")
        |> assert_has("#newsletter-recipient-#{gta.person.id}")
        |> assert_cleared_region()
        |> click_button(tr(locale, "Select visible available recipients"))
        |> assert_has("#newsletter-picker-selected-count",
          text: tr(locale, "%{count} selected", count: 2)
        )
        |> capture(
          locale,
          "Toronto / GTA geography",
          "Broad source text search",
          "Named areas → Toronto / GTA; clear text; Select visible available recipients",
          "Two explicit GTA municipalities match; broad ROCanada is cleared, Burnaby is excluded and two recipients are selected."
        )
        |> select("#mail-geography-areas", tr(locale, "Named areas"), option: [], exact: false)
        |> select("#mail-geography-provinces", tr(locale, "Provinces and territories"),
          option: tr(locale, "British Columbia"),
          exact: false
        )
        |> assert_has("#newsletter-recipient-#{bc.person.id}")
        |> refute_has("#newsletter-recipient-#{toronto.person.id}")
        |> assert_has("#newsletter-picker-selected-count",
          text: tr(locale, "%{count} selected", count: 2)
        )
        |> capture(
          locale,
          "Selection persists outside the filter",
          "Toronto / GTA geography",
          "Clear Named areas; Provinces and territories → British Columbia",
          "The two explicit GTA selections remain selected while British Columbia is displayed. Changing filters does not add recipients."
        )
        |> select("#mail-geography-provinces", tr(locale, "Provinces and territories"),
          option: [],
          exact: false
        )
        |> select("#mail-saved-geography", tr(locale, "Saved geography filter"),
          option: "Custom GTA review",
          exact: false
        )
        |> assert_has("#newsletter-recipient-#{toronto.person.id}")
        |> assert_has("#newsletter-recipient-#{gta.person.id}")
        |> refute_has("#newsletter-recipient-#{bc.person.id}")
        |> capture(
          locale,
          "UI-authored saved geography",
          "Selection persists outside the filter",
          "Clear provinces; Saved geography filter → Custom GTA review",
          "The city/FSA rules created through the existing Lists API match manual contacts without newsletter membership; explicit selections remain unchanged."
        )
        |> click_button("#newsletter-draft-form button", tr(locale, "Save"), exact: true)
        |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)
        |> visit(path)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#newsletter-selected-count",
          text: tr(locale, "%{count} selected", count: 2)
        )
        |> check(
          tr(
            locale,
            "I reviewed the selected contacts' eligibility for this communication. This does not grant newsletter consent."
          )
        )
        |> click_button(tr(locale, "Prepare batch"))
        |> assert_has("#newsletter-batch-review")
        |> open_final_review(path, draft.id)
        |> assert_has("#newsletter-recipients-csv")
        |> capture(
          locale,
          "Reviewed snapshot and CSV",
          "Saved draft reopened",
          "Eligibility review checkbox → Prepare batch → open saved batch review",
          "The immutable reviewed batch has the two selected GTA addresses. The CSV link exports email only; no send or approval is performed."
        )

      PhoenixTest.Playwright.evaluate(
        b,
        "(async () => { const a=document.querySelector('#newsletter-recipients-csv'); const response=await fetch(a.href); return {status:response.status, text:await response.text()}; })()",
        fn result ->
          assert result["status"] == 200

          assert result["text"] ==
                   "\"email\"\r\n\"mississauga@example.org\"\r\n\"toronto@example.org\"\r\n"
        end
      )

      assert {:ok, saved} = Newsletters.Drafts.get(scope, draft.id)
      assert MapSet.new(saved.recipient_keys) == MapSet.new([toronto.person.id, gta.person.id])
      assert Repo.get!(ContactMigration.Contact, legacy.id).source_data == sources_before
      ledgers = Repo.all(Newsletters.Subscription)
      assert length(ledgers) == 2

      assert Enum.all?(
               ledgers,
               &(&1.state == "outreach_only" and is_nil(&1.confirmed_at) and
                   is_nil(&1.consent_version))
             )

      assert Enum.all?(Repo.all(Newsletters.Delivery), &is_nil(&1.attempted_at))
      refute_received {:email, _}

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "MAIL-GEO-01-#{locale}"))
      )

      b
    end

    defp assert_cleared_region(browser) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.querySelector('#draft_region').value",
        fn value ->
          assert value == ""
        end
      )
    end

    defp open_final_review(browser, path, draft_id) do
      batch = Repo.get_by!(Newsletters.Batch, draft_id: draft_id)

      browser
      |> visit(path <> "&step=review&batch=" <> batch.id)
      |> assert_has("[data-phx-main].phx-connected")
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

    defp capture(browser, locale, title, preceding, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      step = Process.get({:mail_geo_step, locale}, 0) + 1
      Process.put({:mail_geo_step, locale}, step)
      filename = "MAIL-GEO-01-#{locale}-#{step}.png"
      PhoenixTest.Playwright.evaluate(browser, "location.href", &Process.put(:mail_geo_url, &1))
      url = AtddEvidence.safe_url(Process.get(:mail_geo_url))
      IO.puts("Capture URL: #{url}")
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(filename, title, outcome, %{
        "scenario_id" => "MAIL-GEO-01-#{locale}",
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "step" => step,
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser)),
        "external_systems" =>
          "Synthetic local contacts only; no sending, provider calls, consent changes or production writes"
      })

      browser
    end
  end
end
