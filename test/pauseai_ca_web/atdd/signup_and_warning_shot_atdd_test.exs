if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.SignupAndWarningShotTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PhoenixTest, except: [fill_in: 3]
    import Ecto.Query, except: [select: 3]
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Engagement, Repo}
    alias PauseAiCa.Accounts.{User, UserToken}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios Enum.map(
                 [
                   {"SIGNUP-01", "Save French questionnaire progress", "French", "Desktop"},
                   {"SIGNUP-02", "Existing member saves a useful resource", "English", "Desktop"},
                   {"SIGNUP-03", "Compact entry creates a real account", "French", "Mobile"},
                   {"SIGNUP-04", "Consent changes analytics, not the experience", "English",
                    "Desktop"},
                   {"SIGNUP-05", "Superadmin acts on an honest cohort funnel", "English",
                    "Desktop"},
                   {"SIGNUP-06", "Recover email delivery and expired continuation", "English",
                    "Desktop"},
                   {"WARN-01", "Read current evidence and send an edited MP letter", "French",
                    "Desktop"},
                   {"WARN-02", "New attention leads to a Montréal action", "English", "Mobile"}
                 ],
                 fn {id, title, language, device} ->
                   %{
                     id: id,
                     title: title,
                     language: language,
                     device: device,
                     roles: [if(id == "SIGNUP-05", do: "Superadmin", else: "Visitor / member")],
                     source_file: __ENV__.file
                   }
                 end
               )

    setup_all do
      AtddEvidence.reset!("M1 signup and Warning Shot acceptance evidence", @scenarios, %{
        browser: "Chromium",
        platform: "Local / CI",
        viewport: "Explicit desktop or mobile per scenario"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup %{conn: browser} do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      previous = Application.get_env(:swoosh, :shared_test_process)
      ga = Application.get_env(:pauseai_ca, :ga_measurement_id)
      Application.put_env(:swoosh, :shared_test_process, self())
      Application.put_env(:pauseai_ca, :ga_measurement_id, "G-ATDDLOCAL")

      on_exit(fn ->
        Application.put_env(:swoosh, :shared_test_process, previous)
        Application.put_env(:pauseai_ca, :ga_measurement_id, ga)
      end)

      intercept_external(browser)
      :ok
    end

    test "SIGNUP-01 questions → actual email → cross-device answers → first action", context do
      id = "SIGNUP-01"
      email = "questions@example.org"
      browser = context.conn |> visit("/fr") |> click("#consent-decline")

      browser =
        answer_questions(browser, "fr")
        |> assert_has("#save-progress-invitation", text: "Créer un compte")
        |> capture(
          id,
          "Answer all three questions",
          "Account value appears after progress; destination contains no answers"
        )

      browser
      |> evaluate("document.querySelector('#save-question-progress').href", fn href ->
        refute href =~ "risk="
      end)

      browser =
        browser
        |> click("#save-question-progress")
        |> fill_in("Courriel", with: "with spaces")
        |> assert_has("#registration_form_email[aria-invalid='true']")
        |> capture(id, "Enter an invalid email", "Inline validation retains the value and task")

      _pending_browser =
        browser
        |> fill_in("Courriel", with: email)
        |> click_button("Envoyez-moi un lien sécurisé")
        |> assert_has("#account-email-pending")
        |> capture(id, "Correct and submit", "One pending account awaits ownership")

      assert %{signup_entry_point: "home_questions", confirmed_at: nil, belief_answers: %{}} =
               Accounts.get_user_by_email(email)

      device =
        new_device(context)
        |> show_email(receive_email(email))
        |> capture(
          id,
          "Open actual delivered confirmation on another device",
          "Synthetic envelope, actual subject and delivered body"
        )

      device =
        device
        |> click_link("Confirm account")
        |> click_button("Confirmer et rester connecté")
        |> assert_path("/fr/tableau-de-bord")
        |> capture(id, "Confirm ownership", "French member next step and saved progress")

      assert Accounts.get_user_by_email(email).belief_answers ==
               Map.new(~w(risk pause coordination), &{&1, "4"})

      assert Engagement.signup_funnel().first_action == 0

      device =
        device
        |> click("header nav > a:first-child")
        |> assert_has("[data-question='risk'] [data-answer='4'][aria-pressed='true']")
        |> capture(
          id,
          "Revisit saved questions",
          "Answers visibly restored without the original local storage"
        )

      device =
        device
        |> click("#account-menu summary")
        |> click_link("Mon tableau de bord")
        |> record_action("fr")
        |> capture(
          id,
          "Record a completed learning action",
          "One first action and a changed next step"
        )

      device |> visit("/fr/tableau-de-bord") |> assert_has("#suggested-next-step")
      assert %{created: 1, confirmed: 1, first_action: 1} = Engagement.signup_funnel()
      assert Repo.aggregate(User, :count) == 1
      finish(id)
    end

    test "SIGNUP-02 existing address → actual sign-in → safe bookmark → replay recovery",
         context do
      id = "SIGNUP-02"
      user = user_fixture(%{email: "existing@example.org"})
      receive_email(user.email)
      {:ok, user} = Accounts.save_resource(user, "pause")

      _pending_browser =
        context.conn
        |> visit("/en/learn")
        |> click("#consent-decline")
        |> capture(id, "Read a useful resource", "Reader can choose to preserve it")
        |> click("#resource-pauseai-learn a[href*='bookmark=']")
        |> fill_in("Email", with: user.email)
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")
        |> capture(id, "Submit existing email", "Same generic pending response")

      assert Accounts.get_user!(user.id).saved_resources == ["pause"]
      delivered = receive_email(user.email)
      assert delivered.subject =~ "Your sign-in link"

      device =
        new_device(context)
        |> show_email(delivered)
        |> capture(id, "Read actual delivered sign-in", "No new account or creation event")
        |> click_link("Sign in")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/en/learn")
        |> assert_has("#resource-pauseai-learn", text: "Saved")
        |> capture(
          id,
          "Prove ownership and return to the resource",
          "Old and new bookmarks coexist"
        )

      assert Accounts.get_user!(user.id).saved_resources == ["pause", "pauseai-learn"]
      assert is_nil(Accounts.get_user!(user.id).signup_entry_point)

      device
      |> visit(email_link(delivered))
      |> assert_has("#login_form_magic")
      |> capture(id, "Reopen used link", "Safe resend instead of replay")

      assert Repo.aggregate(User, :count) == 1
      assert Accounts.get_user!(user.id).saved_resources == ["pause", "pauseai-learn"]
      finish(id)
    end

    @tag browser_context_opts: [viewport: %{width: 390, height: 844}, locale: "fr-CA"]
    test "SIGNUP-03 mobile French entry → new account → returning sign-in → footer source",
         context do
      id = "SIGNUP-03"
      email = "mobile@example.org"

      browser =
        context.conn
        |> visit("/fr")
        |> click("#consent-decline")
        |> assert_has("#account-entry", text: "Connexion / Inscription")
        |> capture(
          id,
          "Browse then choose compact entry",
          "French utility navigation fits narrow mobile"
        )

      assert_no_overflow(browser)

      browser =
        browser
        |> click("#account-entry")
        |> fill_in("Courriel", with: email)
        |> click_button("Envoyez-moi un lien sécurisé")
        |> assert_has("#account-email-pending")
        |> capture(id, "Enter a previously unknown email", "Really creates one pending account")
        |> show_email(receive_email(email))
        |> capture(id, "Open delivered confirmation", "Separate ownership stage")
        |> click_link("Confirm account")
        |> click_button("Confirmer et rester connecté")
        |> assert_path("/fr/tableau-de-bord")
        |> capture(
          id,
          "Confirm and continue",
          "Member next step, not automatic incubator membership"
        )

      assert Accounts.get_user_by_email(email).signup_entry_point == "header"

      _returning_browser =
        browser
        |> press("body", "Control+Home")
        |> click("#flash-info button")
        |> click("#account-menu summary")
        |> click_link("Déconnexion")
        |> assert_has("#account-entry")
        |> click("#flash-info button")
        |> click("#account-entry")
        |> fill_in("Email", with: email)
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")
        |> capture(id, "Sign out and use the same address", "Sign-in, not duplicate creation")

      assert receive_email(email).subject =~ "Your sign-in link"
      assert Repo.aggregate(User, :count) == 1

      new_device(context)
      |> visit("/en")
      |> click("#consent-decline")
      |> click("a[href*='from=home_footer']")
      |> fill_in("Email", with: "footer@example.org")
      |> click_button("Email me a secure link")
      |> assert_has("#account-email-pending")
      |> capture(
        id,
        "Choose homepage footer invitation",
        "Footer source is recorded from actual entry"
      )

      receive_email("footer@example.org")
      assert Accounts.get_user_by_email("footer@example.org").signup_entry_point == "home_footer"
      finish(id)
    end

    test "SIGNUP-04 consent-independent database journeys and safe intercepted GA events",
         context do
      id = "SIGNUP-04"

      denied =
        context.conn
        |> visit("/en")
        |> click("#consent-decline")
        |> click("#account-entry")
        |> fill_in("Email", with: "denied@example.org")
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")
        |> capture(
          id,
          "Decline GA and create account",
          "No Google request; value remains available"
        )

      denied |> evaluate("window.__gaRequests", &assert(&1 == []))

      denied =
        denied
        |> show_email(receive_email("denied@example.org"))
        |> click_link("Confirm account")
        |> click_button("Confirm and stay logged in")
        |> assert_has("#action-editor")
        |> record_action("en")
        |> capture(
          id,
          "Confirm and record action with consent declined",
          "Authoritative stages complete without GA"
        )

      denied |> evaluate("window.__gaRequests", &assert(&1 == []))

      browser =
        new_device(context)
        |> visit("/en")
        |> click("#consent-accept")
        |> click("#account-entry")
        |> fill_in("Email", with: "consented@example.org")
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")
        |> capture(
          id,
          "Consent and create another account",
          "One creation event queued after insertion; Google stays off private page"
        )

      delivered = receive_email("consented@example.org")

      browser =
        browser
        |> click("#continue-browsing")
        |> assert_has("#questions")
        |> capture(id, "Continue browsing", "Queued sign_up reaches locally intercepted GA once")

      assert_ga_events(browser, ["sign_up"])

      browser =
        browser
        |> show_email(delivered)
        |> click_link("Confirm account")
        |> click_button("Confirm and stay logged in")
        |> assert_has("#action-editor")
        |> assert_has("[data-phx-main].phx-connected")
        |> capture(
          id,
          "Confirm owned account with consent granted",
          "Actual confirmation transition before recording an action"
        )
        |> record_action("en")
        |> click("header nav > a:first-child")
        |> assert_has("#questions")
        |> capture(
          id,
          "Confirm, record action and return to public information",
          "One safe confirmation event; same functional outcome"
        )

      assert_ga_events(browser, ["account_confirmed"])
      browser |> visit("/en") |> assert_ga_events([])
      assert %{created: 2, confirmed: 2, first_action: 2} = Engagement.signup_funnel()
      finish(id)
    end

    test "SIGNUP-05 actual signup journeys → admin cohort metrics → source/date filters",
         context do
      id = "SIGNUP-05"

      context.conn
      |> visit("/en")
      |> click("#consent-decline")
      |> click("#account-entry")
      |> fill_in("Email", with: "pending@example.org")
      |> click_button("Email me a secure link")
      |> assert_has("#account-email-pending")
      |> capture(
        id,
        "Create pending header signup",
        "Real email request creates pending cohort member"
      )

      receive_email("pending@example.org")

      late_browser =
        new_device(context)
        |> visit("/en")
        |> click("#consent-decline")
        |> click("a[href*='from=home_footer']")
        |> fill_in("Email", with: "late@example.org")
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")

      late = Accounts.get_user_by_email("late@example.org")
      # Explicit time fixture on the account actually created through UI.
      Repo.update!(
        Ecto.Changeset.change(late, inserted_at: DateTime.add(DateTime.utc_now(:second), -86_400))
      )

      late_browser
      |> show_email(receive_email(late.email))
      |> click_link("Confirm account")
      |> click_button("Confirm and stay logged in")
      |> assert_has("#action-editor")
      |> capture(
        id,
        "Confirm yesterday's signup today",
        "Late confirmation belongs to original creation cohort"
      )

      active =
        new_device(context)
        |> visit("/en")
        |> click("#consent-decline")
        |> click("#account-entry")
        |> fill_in("Email", with: "active@example.org")
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")

      active
      |> show_email(receive_email("active@example.org"))
      |> click_link("Confirm account")
      |> click_button("Confirm and stay logged in")
      |> record_action("en")
      |> capture(
        id,
        "Complete signup and record a real action",
        "Journal submission causes first-action completion"
      )

      historical = user_fixture(%{email: "historical@example.org"})
      receive_email(historical.email)
      admin = user_fixture(%{email: "admin@example.org"})
      receive_email(admin.email)
      admin = Repo.update!(Ecto.Changeset.change(admin, superadmin: true))

      browser =
        new_device(context)
        |> visit("/en")
        |> click("#consent-decline")
        |> click("#account-entry")
        |> fill_in("Email", with: admin.email)
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")

      browser =
        browser
        |> show_email(receive_email(admin.email))
        |> click_link("Sign in")
        |> click_button("Keep me logged in on this device")
        |> assert_has("#action-editor")
        |> click("#flash-info button")
        |> click("#account-menu summary")
        |> click_link("Admin")
        |> assert_has("#signup-created", text: "4")
        |> assert_has("#signup-confirmed", text: "3")
        |> assert_has("#signup-first-action", text: "1")
        |> assert_has("#signup-pending", text: "1")
        |> capture(
          id,
          "Open superadmin metrics",
          "Actual journey-derived counts; explicit historical fixture is unknown, admin excluded"
        )

      today = Date.to_iso8601(Date.utc_today())

      browser =
        browser
        |> fill_in("Created from", with: today)
        |> fill_in("Created through", with: today)
        |> select("Signup source", option: "Header", exact: false)
        |> click_button("Apply filters")
        |> assert_has("#signup-created", text: "2")
        |> assert_has("#signup-confirmed", text: "1")
        |> capture(
          id,
          "Filter today's header cohort",
          "Late footer confirmation does not inflate unrelated signups"
        )

      browser
      |> visit("/admin/dashboard?from=#{today}&to=#{today}&source=header")
      |> assert_has("#signup-created", text: "2")

      assert_sparkline_bounds(browser)

      mobile =
        new_device(context, viewport: %{width: 390, height: 844})
        |> visit("/users/log-in")
        |> fill_in("Email", with: admin.email)
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")
        |> show_email(receive_email(admin.email))
        |> click_link("Sign in")
        |> click_button("Keep me logged in on this device")
        |> assert_has("#action-editor")
        |> visit("/admin/dashboard")
        |> assert_has("#signup-funnel")
        |> capture(
          id,
          "Inspect same real cohort on narrow mobile",
          "Contained cards and sparklines with visible GA coverage limitation"
        )

      assert_sparkline_bounds(mobile)
      finish(id)
    end

    test "SIGNUP-06 failure → honest error → retry → expired link → resend → restored bookmark",
         context do
      id = "SIGNUP-06"
      email = "recover@example.org"
      original = Application.get_env(:pauseai_ca, PauseAiCa.Mailer)
      on_exit(fn -> Application.put_env(:pauseai_ca, PauseAiCa.Mailer, original) end)

      browser =
        context.conn
        |> visit("/en/learn")
        |> click("#consent-decline")
        |> click("#resource-pauseai-learn a[href*='bookmark=']")
        |> fill_in("Email", with: email)

      Application.put_env(:pauseai_ca, PauseAiCa.Mailer, adapter: PauseAiCa.SignupFailureAdapter)

      browser =
        browser
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-error")
        |> capture(
          id,
          "Attempt delivery during temporary failure",
          "Honest retry state, retained task and one pending account"
        )

      assert Repo.aggregate(User, :count) == 1
      Application.put_env(:pauseai_ca, PauseAiCa.Mailer, original)

      browser =
        browser
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")
        |> capture(
          id,
          "Retry after transport recovers",
          "Actual email to same account, no second creation"
        )

      delivered = receive_email(email)

      Repo.update_all(from(t in UserToken, where: t.context == "login"),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -16 * 60)]
      )

      _recovered_browser =
        browser
        |> show_email(delivered)
        |> capture(
          id,
          "Open actual email after explicit token-expiry fixture",
          "Real delivered ownership link is now expired"
        )
        |> click_link("Confirm account")
        |> assert_has("#login_form_magic")
        |> fill_in("Email", with: "different-address@example.org")
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-error")
        |> capture(
          id,
          "Attempt to change address on the expired continuation",
          "Bound task is not copied to a new account; original-address recovery remains available"
        )
        |> fill_in("Email", with: email)
        |> click_button("Email me a secure link")
        |> assert_has("#account-email-pending")
        |> capture(
          id,
          "Use expired-link recovery to resend",
          "Encrypted task context survives expired ownership token"
        )

      new_device(context)
      |> show_email(receive_email(email))
      |> click_link("Confirm account")
      |> click_button("Confirm and stay logged in")
      |> assert_path("/en/learn")
      |> assert_has("#resource-pauseai-learn", text: "Saved")
      |> capture(
        id,
        "Confirm new delivery on another device",
        "Bookmark restored once after ownership; no duplicate account"
      )

      assert Accounts.get_user_by_email(email).saved_resources == ["pauseai-learn"]
      assert Repo.aggregate(User, :count) == 1

      assert Accounts.Onboarding.context(%{"return_to" => "https://evil.example"}, nil)[
               "return_to"
             ] == "/en/dashboard"

      finish(id)
    end

    test "WARN-01 source attribution → MP lookup → edited letter → confirmation → sandbox delivery",
         context do
      id = "WARN-01"

      browser =
        context.conn
        |> visit("/fr")
        |> click("#consent-decline")
        |> capture(
          id,
          "Read current homepage invitation",
          "Wider attention leads to sourced information and Canadian action"
        )
        |> click_link("Derniers développements")
        |> assert_has("#mainstream-safety-context")
        |> assert_has("#update-2026-09-09-wired", text: "8 septembre")
        |> assert_has("#update-2026-09-10-pauseai", text: "Réponse publique et politique")
        |> capture(
          id,
          "Open latest developments",
          "Publication/announcement dates and public response distinguish attributed warnings from incident evidence"
        )

      assert length(
               Regex.scan(
                 ~r{sharp-rise-in-incidents-of-ai-escaping-users-control-research-finds},
                 AtddEvidence.page_html(browser)
               )
             ) == 1

      browser =
        browser
        |> click("#update-2026-09-09-wired a")
        |> capture(
          id,
          "Request cited source",
          "Actual WIRED destination intercepted locally; no fabricated article preview"
        )

      browser
      |> evaluate(
        "window.__externalRequests.at(-1)",
        &assert(&1 =~ "wired.com/story/anthropic-researcher-quits-jacob-coxon")
      )

      browser =
        browser
        |> fill_in("Votre nom", with: "Camille Exemple")
        |> fill_in("Code postal", with: "H2X 1Y4")
        |> click_button("Trouver mon député·e")
        |> assert_has("#letter-form")
        |> capture(
          id,
          "Find MP by postal code",
          "Local Represent stub supplies MP and editable current Canadian ask"
        )
        |> fill_in("Objet", with: "Une pause contraignante pour la sécurité")
        |> fill_in("Message",
          exact: false,
          with:
            "Je vous demande de soutenir une pause contraignante du développement de l'IA avancée à usage général. Camille Exemple."
        )
        |> capture(
          id,
          "Edit and inspect letter",
          "Actual personal words and reviewed subject before dispatch"
        )
        |> fill_in("Votre courriel", with: "constituent@example.org")
        |> click("#send-consent")
        |> click_button("Envoyer la lettre")
        |> assert_has("#awaiting-confirmation")
        |> capture(id, "Explicitly request sending", "Email ownership requested before dispatch")

      browser =
        browser
        |> show_email(receive_email("constituent@example.org"))
        |> capture(
          id,
          "Read actual delivered letter-confirmation email",
          "Safe synthetic envelope, actual subject and body"
        )
        |> click_link("Send my letter")
        |> assert_has("#flash-info")
        |> capture(
          id,
          "Confirm and dispatch in sandbox",
          "No production MP mail; final letter diverted to synthetic sender"
        )

      sent = receive_email("constituent@example.org")
      assert sent.text_body =~ "pause contraignante"

      browser
      |> show_email(sent)
      |> capture(
        id,
        "Read actual sandbox-delivered final letter",
        "Edited subject/body and rehearsal envelope prove dispatch, not live inbox placement"
      )

      assert Repo.aggregate(User, :count) == 0
      finish(id)
    end

    @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
    test "WARN-02 mobile information → tracked Montréal RSVP link → contextual saved progress",
         context do
      id = "WARN-02"

      browser =
        context.conn
        |> visit("/en")
        |> click("#consent-decline")
        |> click_link("Latest developments")
        |> assert_has("#mainstream-safety-context")
        |> capture(
          id,
          "Follow current information",
          "Evidence and Canadian choices available on mobile"
        )
        |> click("#montreal-protest-banner")
        |> capture(
          id,
          "Open Sept. 26 announcement",
          "Real banner click requests existing Luma target; no fabricated RSVP or attendance"
        )

      browser
      |> evaluate("window.__externalRequests.at(-1)", &assert(&1 == "https://luma.com/d40dp5ed"))

      assert Repo.aggregate(
               from(s in Engagement.LearningSignal, where: s.kind == "event_link_opened"),
               :count
             ) == 1

      browser =
        browser
        |> click("header nav > a:first-child")
        |> answer_questions("en")
        |> assert_has("#save-progress-invitation")
        |> capture(
          id,
          "Return and answer questions",
          "Account value is contextual, not automatic incubator enrollment"
        )
        |> click("#save-question-progress")
        |> assert_has("#registration_form")
        |> capture(
          id,
          "Open contextual account path",
          "Signup continuation available without a public group directory"
        )

      assert_no_overflow(browser)
      assert Repo.aggregate(User, :count) == 0
      finish(id)
    end

    defp new_device(context, opts \\ []) do
      config =
        PhoenixTest.Playwright.Config.validate!(
          browser_context_opts: Keyword.merge([viewport: %{width: 1280, height: 900}], opts)
        )

      PhoenixTest.Playwright.Case.new_session(config, context) |> tap(&intercept_external/1)
    end

    defp fill_in(browser, label, opts) do
      browser
      |> assert_has("[data-phx-main].phx-connected")
      |> PhoenixTest.fill_in(label, opts)
    end

    defp intercept_external(browser) do
      {:ok, _} =
        PlaywrightEx.BrowserContext.add_init_script(browser.context_id,
          timeout: 5_000,
          source: """
            window.__gaRequests = []; window.__externalRequests = [];
            const append = Node.prototype.appendChild;
            Node.prototype.appendChild = function(node) {
              if (node.tagName === 'SCRIPT' && node.src.includes('googletagmanager.com')) {
                window.__gaRequests.push(node.src); node.removeAttribute('src');
              }
              return append.call(this, node);
            };
            document.addEventListener('click', event => {
              const link = event.target.closest?.('a[href]');
              if (link && link.href.startsWith('https://') && new URL(link.href).origin !== location.origin) {
                window.__externalRequests.push(link.href); event.preventDefault();
              }
            }, true);
          """
        )

      browser
    end

    defp receive_email(recipient) do
      assert_receive {:email, email}, 8_000
      assert Enum.any?(email.to, fn {_name, address} -> address == recipient end)
      assert email.from == {"PauseAI Canada", "campaigns@example.org"}
      assert email.cc == [] and email.bcc == []

      assert is_binary(email.subject) and is_binary(email.html_body) and
               is_binary(email.text_body)

      email
    end

    defp email_link(email) do
      [_, link] =
        Regex.run(
          ~r{href="(https?://[^"]+/(?:users/log-in/|letters/confirm/)[^"]+)"},
          email.html_body
        )

      String.replace(link, "&amp;", "&")
    end

    defp show_email(browser, email) do
      escape = fn value ->
        value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      end

      [_, body] = Regex.run(~r{<body[^>]*>(.*)</body>}s, email.html_body)

      html = """
        <html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;background:#eee;font:16px/1.5 system-ui}header{background:#171717;color:white;padding:20px}section{padding:20px;background:white;max-width:850px;margin:20px auto}h1{font-size:22px}dt{font-weight:bold}dd{margin:0 0 10px}a{overflow-wrap:anywhere}</style>
        <header>Captured test inbox · Actual Swoosh delivery · No live Brevo transport</header><section id="delivered-email"><h1>#{escape.(email.subject)}</h1><dl><dt>From</dt><dd>#{escape.(inspect(email.from))}</dd><dt>To</dt><dd>#{escape.(inspect(email.to))}</dd><dt>Cc / Bcc</dt><dd>None</dd></dl>#{body}</section></html>
      """

      visit(browser, "data:text/html;base64," <> Base.encode64(html))
    end

    defp answer_questions(browser, locale) do
      Enum.reduce(~w(risk pause coordination), browser, fn question, b ->
        click_button(
          b,
          "[data-question='#{question}']",
          if(locale == "fr", do: "Plutôt", else: "Agree"),
          exact: true
        )
      end)
    end

    defp record_action(browser, "fr"),
      do:
        browser
        |> assert_has("[data-phx-main].phx-connected")
        |> select("Qu'avez-vous fait?", option: "Lu ou regardé une ressource", exact: false)
        |> click_button("Noter en privé")
        |> assert_has("#suggested-next-step")

    defp record_action(browser, _),
      do:
        browser
        |> assert_has("[data-phx-main].phx-connected")
        |> select("What did you do?", option: "Read or watched a resource", exact: false)
        |> click_button("Record privately")
        |> assert_has("#suggested-next-step")

    defp assert_ga_events(browser, expected) do
      evaluate(
        browser,
        "JSON.parse(JSON.stringify((window.dataLayer||[]).map(args=>Array.from(args)).filter(args=>args[0]==='event'&&['sign_up','account_confirmed'].includes(args[1]))))",
        fn requests ->
          assert Enum.map(requests, &Enum.at(&1, 1)) == expected
          raw = Jason.encode!(requests)
          refute raw =~ "@"
          refute raw =~ "flow="
          refute raw =~ "/users/log-in/"

          for [_event, _name, params] <- requests do
            assert Enum.sort(Map.keys(params)) ==
                     Enum.sort(~w(method signup_entry_point page_location page_referrer))

            assert params["method"] == "email_link"
            assert params["signup_entry_point"] in Accounts.Onboarding.sources()
          end
        end
      )
    end

    defp assert_no_overflow(browser),
      do: evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))

    defp assert_sparkline_bounds(browser),
      do:
        evaluate(
          browser,
          "[...document.querySelectorAll('#signup-funnel svg')].every(svg=>{const a=svg.getBoundingClientRect(),b=svg.closest('[id^=signup-]').getBoundingClientRect();return a.left>=b.left&&a.right<=b.right&&a.top>=b.top&&a.bottom<=b.bottom})",
          &assert(&1)
        )

    defp capture(browser, id, trigger, outcome) do
      scenario = Enum.find(@scenarios, &(&1.id == id))
      step = Process.get({:step, id}, 0) + 1
      Process.put({:step, id}, step)
      filename = "#{id}-#{String.pad_leading(to_string(step), 2, "0")}.png"
      started = System.monotonic_time(:millisecond)

      AcceptanceHarness.Evidence.record_pending_step(
        filename,
        scenario.title,
        trigger <> " → " <> outcome,
        %{"scenario_id" => id, "step" => to_string(step), "user" => hd(scenario.roles)}
      )

      browser = AtddEvidence.capture_full_page(browser, filename)

      evaluate(
        browser,
        "({url:location.href,width:innerWidth,height:innerHeight,language:document.documentElement.lang})",
        &Process.put(:evidence_context, &1)
      )

      actual = Process.get(:evidence_context)

      AtddEvidence.record_step(filename, scenario.title, trigger <> " → " <> outcome, %{
        "scenario_id" => id,
        "step" => to_string(step),
        "current_url" => AtddEvidence.safe_url(actual["url"]),
        "language" =>
          if(actual["url"] =~ "data:", do: "Bilingual email", else: actual["language"]),
        "device" =>
          "#{if(actual["width"] <= 600, do: "Mobile", else: "Desktop")} #{actual["width"]}×#{actual["height"]}",
        "user" => hd(scenario.roles),
        "click_target" => trigger,
        "duration_ms" => System.monotonic_time(:millisecond) - started,
        "geometry" => Process.get(:evidence_geometry),
        "external_systems" =>
          "Swoosh Test delivery; Brevo/Represent local stubs; GA script and outbound links locally intercepted; no live external writes"
      })

      browser
    end

    defp finish(id) do
      scenario = Enum.find(@scenarios, &(&1.id == id))
      AtddEvidence.mark_scenario_success!(scenario)
      AcceptanceHarness.Evidence.record_current_scenario_runtime(scenario)
    end
  end
end
