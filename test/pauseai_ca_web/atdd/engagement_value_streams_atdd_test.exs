if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.EngagementValueStreamsTest do
    use PhoenixTest.Playwright.Case, async: false

    import PauseAiCa.AccountsFixtures

    alias AcceptanceHarness.BrowserScreenshot
    alias PauseAiCa.{Engagement, Repo}
    alias PauseAiCaWeb.AtddEvidence

    @moduletag :atdd

    @scenarios [
      %{
        id: "interest-to-understanding",
        title: "A visitor moves from concern to an informed view",
        roles: ["Visitor"],
        language: "French",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "understanding-to-engagement",
        title: "A member records progress and receives an attainable next step",
        roles: ["Member"],
        language: "French",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "interest-to-understanding-saved-path",
        title: "Anonymous learning signals become one distinct learner after sign-in",
        roles: ["Visitor"],
        language: "French",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "warning-shot-to-political-contact",
        title: "A constituent turns a warning shot into a message to their MP",
        roles: ["Constituent"],
        language: "French",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "superadmin-monitors-capacity",
        title: "A superadmin monitors first-party movement metrics",
        roles: ["Superadmin"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "superadmin-transfers-access",
        title: "A superadmin transfers administration to a new account",
        roles: ["Existing superadmin", "New account holder"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      }
    ]

    test "the principal interest and engagement value streams are visible", %{conn: conn} do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      AtddEvidence.reset!("PauseAI Canada engagement acceptance evidence", @scenarios, %{
        browser: "Chromium",
        platform: "GitHub Actions",
        viewport: "Desktop"
      })

      conn
      |> visit("/fr/strategie")
      |> assert_has("#strategy")
      |> capture(
        "engagement-01-strategy.png",
        Enum.at(@scenarios, 0),
        "The French strategy explains how informed interest can become collective capacity"
      )

      conn
      |> visit("/fr")
      |> click_button(~s([data-question="risk"]), "Plutôt")
      |> assert_has("#local-status", text: "Réponse enregistrée.")
      |> click_button(~s([data-question="pause"]), "Plutôt")
      |> click_button(~s([data-question="coordination"]), "Plutôt")
      |> evaluate(
        """
        (() => {
          const csrfToken = document.querySelector("meta[name='csrf-token']").content
          return Promise.all(["risk", "pause", "coordination"].map((question, index) =>
            fetch(`/learning/questions/${question}`, {
              method: "POST",
              headers: {"content-type": "application/json", "x-csrf-token": csrfToken},
              body: JSON.stringify({answer: "4", complete: index === 2})
            })
          )).then(responses => responses.map(response => response.status))
        })()
        """,
        &assert(&1 == [200, 200, 200])
      )
      |> assert_has("#save-progress-invitation", text: "Créer un compte")
      |> assert_has("a[href='/users/register?bookmark=risk']", text: "Enregistrer")
      |> assert_has("a[href='/fr/confidentialite']", text: "Politique de confidentialité")
      |> capture(
        "engagement-02-saved-learning-path.png",
        Enum.at(@scenarios, 2),
        "After answering the three questions, a visitor can save progress or bookmark one useful argument with only an email account"
      )
      |> visit("/fr/comprendre")
      |> assert_has(
        "#resource-pauseai-learn a[href='/users/register?bookmark=pauseai-learn']",
        text: "Enregistrer"
      )

      conn
      |> visit("/fr/tir-de-semonce")
      |> assert_has("#mp-lookup-form")
      |> capture(
        "engagement-03-warning-shot.png",
        Enum.at(@scenarios, 3),
        "The Warning Shot offers a concrete route from concern to political contact"
      )

      member = user_fixture()
      {login_token, _token} = generate_user_magic_link_token(member)

      browser =
        conn
        |> visit("/users/log-in/#{login_token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")

      browser =
        browser
        |> visit("/fr/profil")
        |> fill_in("Code postal complet", with: "H2X 1Y4")
        |> check("M’envoyer des nouvelles locales pertinentes")
        |> click_button("Trouver mon député")
        |> assert_has("#mp-result", text: "Steven Guilbeault")
        |> assert_has("#mp-position", text: "pas encore documentée")
        |> visit("/fr/tableau-de-bord")
        |> assert_has("#dashboard-mp", text: "Steven Guilbeault")
        |> assert_has("#action-form")
        |> evaluate("""
        (() => {
          const field = document.querySelector("#action_action_type");
          field.value = "learned";
          field.dispatchEvent(new Event("change", {bubbles: true}));
        })()
        """)
        |> fill_in("Quand?", with: Date.to_iso8601(Date.utc_today()))
        |> click_button("Noter en privé")
        |> assert_has("#suggested-next-step", text: "En parler à une personne")

      browser
      |> visit("/fr/tableau-de-bord")
      |> assert_has("#suggested-next-step", text: "En parler à une personne")
      |> refute_has("#pending-actions")
      |> capture(
        "engagement-04-member-next-step.png",
        Enum.at(@scenarios, 1),
        "A member-recorded learning action still changes the suggested next step after refresh"
      )

      assert %{
               people: 1,
               breakdown: %{
                 question_answers: 1,
                 questionnaires_completed: 1,
                 learn_page_visitors: 1,
                 self_reported: 1
               }
             } = Engagement.learning_metrics()

      _admin = member |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

      browser
      |> visit("/admin/dashboard")
      |> assert_has("#metric-actions")
      |> assert_has("#metrics-by-type")
      |> assert_has("#learning-breakdown summary", text: "1 person")
      |> evaluate("document.querySelector('#learning-breakdown').open = true")
      |> assert_has("#questions-answered", text: "1")
      |> assert_has("#questionnaire-completed", text: "1")
      |> assert_has("#learn-visited", text: "1")
      |> assert_has("#learning-self-reported", text: "1")
      |> capture(
        "engagement-05-admin-metrics.png",
        Enum.at(@scenarios, 4),
        "The superadmin sees aggregate movement progress from first-party database records"
      )

      transfer_scenario = Enum.at(@scenarios, 5)
      newcomer_email = "new-superadmin@example.com"

      browser =
        browser
        |> visit("/admin/accounts")
        |> assert_has("#admin-user-#{member.id}", text: member.email)
        |> refute_has("#admin-users", text: newcomer_email)
        |> capture(
          "engagement-06-accounts-before.png",
          transfer_scenario,
          "The existing superadmin sees the account list before the newcomer registers",
          step: "1/3",
          user: "Existing superadmin"
        )
        |> log_out()

      browser =
        browser
        |> visit("/users/register")
        |> fill_in("Email · Courriel", with: newcomer_email)
        |> click_button("Create account · Créer le compte")
        |> assert_path("/users/log-in")
        |> assert_has("[role='alert']", text: newcomer_email)

      newcomer = PauseAiCa.Accounts.get_user_by_email(newcomer_email)
      {newcomer_token, _token} = generate_user_magic_link_token(newcomer)

      browser =
        browser
        |> visit("/users/log-in/#{newcomer_token}")
        |> click_button("Confirm and stay logged in")
        |> assert_path("/")
        |> log_out()

      {member_token, _token} = generate_user_magic_link_token(member)

      browser =
        browser
        |> visit("/users/log-in/#{member_token}")
        |> click_button("Keep me logged in on this device")
        |> visit("/admin/accounts")
        |> assert_has("#admin-user-#{newcomer.id}", text: newcomer_email)
        |> assert_has("#admin-toggle-#{newcomer.id}", text: "Make superadmin")
        |> click("#admin-toggle-#{newcomer.id}")
        |> assert_has("#admin-user-#{newcomer.id}", text: "Superadmin")
        |> capture(
          "engagement-07-accounts-new-superadmin.png",
          transfer_scenario,
          "After the newcomer creates and confirms an account, the existing superadmin grants access",
          step: "2/3",
          user: "Existing superadmin"
        )
        |> log_out()

      {promoted_token, _token} = generate_user_magic_link_token(newcomer)

      browser
      |> visit("/users/log-in/#{promoted_token}")
      |> click_button("Keep me logged in on this device")
      |> visit("/admin/accounts")
      |> assert_has("#admin-user-#{member.id}", text: "Superadmin")
      |> click("#admin-toggle-#{member.id}")
      |> assert_has("#admin-toggle-#{member.id}", text: "Make superadmin")
      |> assert_has("#admin-toggle-#{newcomer.id}", text: "Remove role")
      |> tap(fn _browser ->
        refute PauseAiCa.Accounts.get_user!(member.id).superadmin
        assert PauseAiCa.Accounts.get_user!(newcomer.id).superadmin
      end)
      |> capture(
        "engagement-08-accounts-transfer-complete.png",
        transfer_scenario,
        "The new superadmin removes access from the previous superadmin and remains the administrator",
        step: "3/3",
        user: "New account holder"
      )

      Enum.each(@scenarios, &AtddEvidence.mark_scenario_success!/1)
      AtddEvidence.finalize!()
    end

    defp capture(conn, filename, scenario, description, opts \\ []) do
      started_at = System.monotonic_time(:millisecond)
      conn = BrowserScreenshot.capture(conn, filename, &PhoenixTest.Playwright.screenshot/2)
      duration_ms = System.monotonic_time(:millisecond) - started_at

      AtddEvidence.record_step(filename, scenario.title, description, %{
        "scenario_id" => scenario.id,
        "scenario" => scenario.title,
        "step" => Keyword.get(opts, :step, "1/1"),
        "current_url" => "browser",
        "language" => scenario.language,
        "device" => scenario.device,
        "user" => Keyword.get(opts, :user, hd(scenario.roles)),
        "click_target" => "-",
        "duration_ms" => duration_ms
      })

      AtddEvidence.record_scenario_runtime(scenario, duration_ms)

      conn
    end

    defp log_out(browser) do
      browser
      |> evaluate("document.querySelector('#account-menu').open = true")
      |> click_link("Log out")
      |> assert_path("/")
    end
  end
end
