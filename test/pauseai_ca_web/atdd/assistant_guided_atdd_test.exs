if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.AssistantGuidedTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    import Ecto.Query
    alias PauseAiCa.{Accounts, Assistant, CRM, ContactMigration, GuidedModeFixtures, Repo}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "CRM-ASSIST-GUIDE-01-#{locale}",
                     title: "Read-only configured geography wizard · #{language}",
                     roles: ["Superadmin"],
                     language: language,
                     device: device,
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!("Guided assistant · read-only Contacts journey", @scenarios, %{
        browser: "Chromium",
        fixture: "Synthetic fixture provider and isolated contacts only"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-ASSIST-GUIDE-01 reviewed JSON guides actual menu and configured area #{locale}",
           c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      old_config = Application.fetch_env(:pauseai_ca, :agent_assistant)

      env_before =
        Map.new(["PAUSEAI_CA_RELEASE_ID", "PAUSEAI_CA_GIT_SHA"], &{&1, System.get_env(&1)})

      Application.put_env(:pauseai_ca, :agent_assistant, GuidedModeFixtures.configuration(self()))
      System.put_env("PAUSEAI_CA_RELEASE_ID", "guided-synthetic-fixture")
      System.put_env("PAUSEAI_CA_GIT_SHA", String.duplicate("a", 40))

      on_exit(fn ->
        case old_config do
          {:ok, value} -> Application.put_env(:pauseai_ca, :agent_assistant, value)
          :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
        end

        Enum.each(env_before, fn {key, value} ->
          if value, do: System.put_env(key, value), else: System.delete_env(key)
        end)
      end)

      user = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      scope = Accounts.Scope.for_user(user)
      assert {:ok, _} = Assistant.set_enabled(scope, true)

      {:ok, toronto} =
        CRM.create(scope, %{
          email: "guided-toronto@example.invalid",
          name: "Synthetic Toronto",
          city: "Toronto"
        })

      {:ok, gta} =
        CRM.create(scope, %{
          email: "guided-gta@example.invalid",
          name: "Synthetic Mississauga",
          city: "Mississauga"
        })

      {:ok, %{contacts: [bc]}} =
        ContactMigration.import_selected(
          [
            %{
              "email" => "guided-bc@example.invalid",
              "name" => "Synthetic Burnaby",
              "city" => "Burnaby",
              "province" => "BC",
              "source_observation" => %{"user" => %{"timezone" => "America/Toronto"}}
            }
          ],
          "synthetic.csv",
          "guided-fixture",
          user
        )

      {:ok, unknown} =
        CRM.create(scope, %{email: "guided-unknown@example.invalid", name: "Synthetic Unknown"})

      raw_before = Repo.get!(ContactMigration.Contact, bc.id).source_data
      count_before = Repo.aggregate(PhoenixCRM.Person, :count)
      sources_before = Repo.all(from(s in PhoenixCRM.Source, select: s.original))
      flush_mail()
      {token, _} = generate_user_magic_link_token(user)
      id = "CRM-ASSIST-GUIDE-01-" <> locale

      browser =
        c.conn
        |> visit("/users/log-in/#{token}?locale=#{locale}")
        |> click_button(tr(locale, "Keep me logged in on this device"))
        |> assert_path("/")
        |> assert_has("#account-menu")
        |> visit("/admin/assistant?locale=#{locale}")
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has(".phx-connected #site-assistant-launcher")
        |> click_button("#site-assistant-launcher", tr(locale, "Assistant"))
        |> assert_has("#site-assistant-dialog[open]")
        |> check(tr(locale, "Guided mode"))
        |> fill_in("#site-assistant-text", tr(locale, "Message"),
          with: "Show the configured Toronto / GTA area"
        )
        |> capture(
          id,
          "Guided mode selected",
          "Actual assistant panel on Assistant settings",
          "Guided mode checkbox and Message field",
          "The user explicitly chooses Guided mode before submitting the single synthetic generation."
        )
        |> click_button("#site-assistant-form button[type=submit]", tr(locale, "Send"))
        |> assert_has("#site-assistant-guide-step",
          text: tr(locale, "Step 1 of 2 · Open Contacts through the Manage menu.")
        )
        |> capture(
          id,
          "Reviewed guide ready",
          "Assistant with Guided mode selected",
          "Send",
          "Reviewed structured output becomes two explicit human-paced steps; no contact query has run through a model."
        )
        |> click_button("#site-assistant-guide-next", tr(locale, "Next"))
        |> assert_has("#crm-directory")
        |> assert_has("#site-assistant-guide-step",
          text: tr(locale, "Step 2 of 2 · Choose %{area} in Named areas.", area: "Toronto / GTA")
        )
        |> capture(
          id,
          "Actual Contacts menu navigation",
          "Guide step 1",
          "Next",
          "The actual registered Manage Contacts menu link opened the expected locale URL and server directory."
        )
        |> click_button("#site-assistant-guide-next", tr(locale, "Next"))
        |> assert_has("#site-assistant-guide-step",
          text: tr(locale, "Complete · %{count} contacts match this area.", count: 2)
        )
        |> assert_has("#crm-contact-#{toronto.person.id}")
        |> assert_has("#crm-contact-#{gta.person.id}")
        |> refute_has("#crm-contact-#{unknown.person.id}")
        |> refute_has("li", text: "Synthetic Burnaby")
        |> evaluate("document.activeElement.id", &assert(&1 == "crm-areas"))
        |> capture(
          id,
          "Configured area verified",
          "Guide step 2 on Contacts",
          "Next",
          "Actual URL, selected area, focus and fresh server count agree. The screenshot helper removes native caret focus; the registered target ring remains. BC timezone-only and unknown rows are excluded."
        )

      evaluate(
        browser,
        "document.querySelector('#crm-areas').value",
        &assert(&1 == "toronto_gta")
      )

      browser =
        browser
        |> click_button("#site-assistant-guide-back", tr(locale, "Back"))
        |> assert_has("#site-assistant-guide-next:not([disabled])")
        |> click_button("#site-assistant-guide-next", tr(locale, "Next"))
        |> assert_has("#site-assistant-guide-step",
          text: tr(locale, "Complete · %{count} contacts match this area.", count: 2)
        )
        |> click_button("#site-assistant-guide-exit", tr(locale, "Exit"))
        |> refute_has("#site-assistant-guide")
        |> evaluate("document.activeElement.id", &assert(&1 == "site-assistant-launcher"))
        |> capture(
          id,
          "Guide exited with data intact",
          "Verified area results",
          "Exit",
          "Highlights stop, the conversation remains available, and no contact, consent, draft or delivery changed."
        )

      assert_received {:guided_provider_called, _}
      refute_received {:guided_provider_called, _}
      assert Repo.aggregate(PhoenixCRM.Person, :count) == count_before
      assert Repo.all(from(s in PhoenixCRM.Source, select: s.original)) == sources_before
      assert Repo.get!(ContactMigration.Contact, bc.id).source_data == raw_before
      assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == 0
      assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
      refute_received {:email, _}
      AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      browser
    end

    defp tr(locale, text, bindings \\ []),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text, bindings)
        end)

    defp flush_mail do
      receive do
        {:email, _} -> flush_mail()
      after
        0 -> :ok
      end
    end

    defp capture(browser, id, title, preceding, control, outcome) do
      evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      evaluate(browser, "location.href", &Process.put(:guided_capture_url, &1))
      url = AtddEvidence.safe_url(Process.get(:guided_capture_url))
      IO.puts("Capture URL: #{url}")
      step = Process.get({:guided_step, id}, 0) + 1
      Process.put({:guided_step, id}, step)
      file = "#{id}-#{step}.png"

      metadata = %{
        "scenario_id" => id,
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "step" => step,
        "fixture" => "Synthetic isolated contacts; no paid provider or external delivery"
      }

      AcceptanceHarness.Evidence.record_pending_step(file, title, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, file)

      AtddEvidence.record_step(
        file,
        title,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
