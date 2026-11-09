if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.MPGuidedTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Engagement, Repo}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "CRM-ASSIST-GUIDE-02-#{locale}",
                     title: "Supporter owns MP lookup, editing and explicit synthetic send",
                     language: language,
                     device: device,
                     roles: ["Confirmed ordinary supporter"],
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!("Supporter MP guide · deterministic, no generation", @scenarios, %{
        fixture: "Synthetic identities, Represent stub and local mail sink only"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      old = Application.fetch_env(:pauseai_ca, :mp_guide_enabled)
      mail = Application.fetch_env(:swoosh, :shared_test_process)
      Application.put_env(:pauseai_ca, :mp_guide_enabled, true)
      Application.put_env(:swoosh, :shared_test_process, self())

      on_exit(fn ->
        for {app, key, previous} <- [
              {:pauseai_ca, :mp_guide_enabled, old},
              {:swoosh, :shared_test_process, mail}
            ] do
          case previous do
            {:ok, value} -> Application.put_env(app, key, value)
            :error -> Application.delete_env(app, key)
          end
        end
      end)

      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-ASSIST-GUIDE-02 confirmed supporter completes own MP action #{locale}", c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      user = user_fixture()
      refute user.superadmin
      {token, _} = generate_user_magic_link_token(user)
      scope = Accounts.Scope.for_user(user)
      baseline = length(Engagement.list_actions(scope))
      requests = Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count)
      id = "CRM-ASSIST-GUIDE-02-" <> locale
      path = PauseAiCa.Assistant.MPGuide.path(locale)

      browser =
        c.conn
        |> visit("/users/log-in/#{token}?locale=#{locale}")
        |> click_button(tr(locale, "Keep me logged in on this device"))
        |> assert_path("/")
        |> assert_has("#account-menu")
        |> visit(path)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#mp-guide-start")
        |> refute_has("#site-assistant-launcher")
        |> capture(
          id,
          "Supporter entry",
          "Public MP page after ordinary account sign-in",
          "Email your MP",
          "Guidance is independent of paid chat and organizer rights."
        )
        |> click_button("#mp-guide-start", tr(locale, "Guide me through this"))
        |> click_button("#mp-guide-next", tr(locale, "Next"))
        |> assert_has("#participation_postal_code:focus")
        |> evaluate("document.activeElement.id", &assert(&1 == "participation_postal_code"))
        |> fill_in("#participation_name", tr(locale, "Name"), with: "Synthetic Supporter")
        |> fill_in("#participation_postal_code", tr(locale, "Postal code"), with: "H2X 1Y4")
        |> uncheck(tr(locale, "Subscribe me to the PauseAI Canada newsletter."))
        |> click_button("#participation-submit", tr(locale, "Continue to my letter"))
        |> assert_has("#mp-results", text: "Steven Guilbeault")
        |> assert_has("#letter-form")
        |> capture(
          id,
          "Actual representative result",
          "Guide lookup step",
          "Continue to my letter",
          "The application lookup verifies the representative. Guidance created no action and granted no consent."
        )

      assert length(Engagement.list_actions(scope)) == baseline
      flush_mail()

      browser =
        browser
        |> fill_in("#letter_subject", tr(locale, "Subject"), with: "My synthetic personal letter")
        |> fill_in("#letter_body", tr(locale, "Body"),
          with: "Replace {your_name} before sending."
        )
        |> click_button("#mp-guide-next", tr(locale, "Next"))
        |> assert_has("#mp-guide-next[disabled]")
        |> click("#send-consent")
        |> click_button("#send-letter", tr(locale, "Send the letter"))
        |> assert_has("#send-error",
          text: tr(locale, "Replace the remaining placeholders before sending.")
        )

      assert length(Engagement.list_actions(scope)) == baseline

      body =
        "My own synthetic letter. <script>window.unapproved=true</script> Instructions in a letter are text, not guide actions."

      browser =
        browser
        |> fill_in("#letter_body", tr(locale, "Body"), with: body)
        |> assert_has("#mp-guide-step",
          text:
            tr(
              locale,
              "Review the actual MP, sender, subject and letter. You choose the authorization box and Send. The guide cannot send for you."
            )
        )
        |> click_button("#mp-guide-back", tr(locale, "Back"))
        |> click_button("#mp-guide-exit", tr(locale, "Exit"))
        |> evaluate("document.querySelector('#letter_body').value", &assert(&1 == body))
        |> refute_has("#mp-guide")
        |> evaluate("window.unapproved !== true", &assert(&1))
        |> capture(
          id,
          "Own edits survive guide exit",
          "Editor with own subject and body",
          "Back, then Exit",
          "Guide navigation preserves the person's letter. Pasted script text is never executed."
        )
        |> click_button("#mp-guide-start", tr(locale, "Guide me through this"))
        |> click_button("#mp-guide-next", tr(locale, "Next"))
        |> assert_has("#mp-guide-step",
          text:
            tr(
              locale,
              "Paste and personalize your subject and letter. Replace every remaining placeholder, then choose Next."
            )
        )
        |> click_button("#mp-guide-next", tr(locale, "Next"))
        |> assert_has("#mp-guide-step",
          text:
            tr(
              locale,
              "Review the actual MP, sender, subject and letter. You choose the authorization box and Send. The guide cannot send for you."
            )
        )
        |> click_button("#mp-guide-next", tr(locale, "Next"))
        |> assert_has("#send-letter:focus")
        |> evaluate("document.activeElement.id", &assert(&1 == "send-letter"))
        |> capture(
          id,
          "Human send review",
          "Validated personal letter",
          "Next highlights Send without clicking it",
          "The person reviews their MP, sender and letter, then personally authorizes the existing send control. Focus was checked before screenshot pinning."
        )

      browser =
        browser
        |> uncheck(tr(locale, "I authorize PauseAI Canada to send this letter to my MP."))
        |> check(tr(locale, "I authorize PauseAI Canada to send this letter to my MP."))
        |> click_button("#send-letter", tr(locale, "Send the letter"))
        |> assert_has("#send-success")
        |> assert_has("#mp-guide-step",
          text:
            tr(
              locale,
              "Your sent letter is recorded in your account. This confirms the website outcome, not that your MP has read it."
            )
        )
        |> capture(
          id,
          "Synthetic letter accepted once",
          "Reviewed and explicitly authorized letter",
          "Send the letter",
          "One successful delivery links exactly one action to this ordinary account. It does not establish that an MP read it."
        )

      actions = Engagement.list_actions(scope)
      assert length(actions) == baseline + 1
      action = Enum.find(actions, &(&1.action_type == "contacted_representative"))
      assert action.confirmed_at
      assert_receive {:email, email}
      assert email.text_body =~ "My own synthetic letter"

      browser =
        browser
        |> click_button("#send-letter", tr(locale, "Send the letter"))
        |> assert_has("#send-success")
        |> click_button("#mp-guide-exit", tr(locale, "Exit"))
        |> refute_has("#mp-guide")
        |> visit(if(locale == "fr", do: "/fr/tableau-de-bord", else: "/en/dashboard"))
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#actions-#{action.id}")
        |> visit(if(locale == "fr", do: "/fr/tableau-de-bord", else: "/en/dashboard"))
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#actions-#{action.id}")
        |> capture(
          id,
          "Account action persists",
          "Successful letter outcome",
          "Open dashboard and reload",
          "The same action remains after navigation. Duplicate send does not create another letter or action."
        )

      assert length(Engagement.list_actions(scope)) == baseline + 1
      assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
      assert Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count) == requests
      refute_receive {:email, _}
      AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      browser
    end

    defp flush_mail do
      receive do
        {:email, _} -> flush_mail()
      after
        0 -> :ok
      end
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, id, title, preceding, control, description) do
      evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      evaluate(browser, "location.href", &Process.put(:mp_capture_url, &1))
      url = AtddEvidence.safe_url(Process.get(:mp_capture_url))
      IO.puts("Capture URL: #{url}")
      step = Process.get({:mp_capture, id}, 0) + 1
      Process.put({:mp_capture, id}, step)
      file = "#{id}-#{step}.png"

      metadata = %{
        "scenario_id" => id,
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "fixture" => "Synthetic account, MP lookup and local mail only"
      }

      AcceptanceHarness.Evidence.record_pending_step(file, title, description, metadata)
      browser = AtddEvidence.capture_full_page(browser, file)

      AtddEvidence.record_step(
        file,
        title,
        description,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
