if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.EngagementValueStreamsTest do
    use PhoenixTest.Playwright.Case, async: false

    import PauseAiCa.AccountsFixtures

    alias AcceptanceHarness.BrowserScreenshot
    alias PauseAiCa.Repo
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
        title: "A curious visitor saves a personal path before joining",
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
      |> evaluate("""
      (() => {
        document.querySelectorAll(".belief-question").forEach((question) => {
          question.querySelector('[data-answer="4"]').click()
        })
      })()
      """)
      |> assert_has("#save-progress-invitation", text: "Créer un compte")
      |> assert_has("a[href='/users/register?bookmark=risk']", text: "Enregistrer")
      |> assert_has("a[href='/fr/confidentialite']", text: "Politique de confidentialité")
      |> capture(
        "engagement-02-saved-learning-path.png",
        Enum.at(@scenarios, 2),
        "After answering the three questions, a visitor can save progress or bookmark one useful argument with only an email account"
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

      _admin = member |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

      browser
      |> visit("/admin/metrics")
      |> assert_has("#metric-actions")
      |> assert_has("#metrics-by-type")
      |> capture(
        "engagement-05-admin-metrics.png",
        Enum.at(@scenarios, 4),
        "The superadmin sees aggregate movement progress from first-party database records"
      )

      Enum.each(@scenarios, &AtddEvidence.mark_scenario_success!/1)
      AtddEvidence.finalize!()
    end

    defp capture(conn, filename, scenario, description) do
      started_at = System.monotonic_time(:millisecond)
      conn = BrowserScreenshot.capture(conn, filename, &PhoenixTest.Playwright.screenshot/2)
      duration_ms = System.monotonic_time(:millisecond) - started_at

      AtddEvidence.record_step(filename, scenario.title, description, %{
        "scenario_id" => scenario.id,
        "scenario" => scenario.title,
        "step" => "1/1",
        "current_url" => "browser",
        "language" => scenario.language,
        "device" => scenario.device,
        "user" => hd(scenario.roles),
        "click_target" => "-",
        "duration_ms" => duration_ms
      })

      AtddEvidence.record_scenario_runtime(scenario, duration_ms)

      conn
    end
  end
end
