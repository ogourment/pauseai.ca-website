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
      |> assert_has("#engagement-ladder")
      |> capture(
        "engagement-01-strategy.png",
        Enum.at(@scenarios, 0),
        "The French strategy explains how informed interest can become collective capacity"
      )

      conn
      |> visit("/fr/tir-de-semonce")
      |> assert_has("#mp-lookup-form")
      |> capture(
        "engagement-02-warning-shot.png",
        Enum.at(@scenarios, 2),
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
        |> visit("/fr/actions")
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
      |> visit("/fr/actions")
      |> assert_has("#suggested-next-step", text: "En parler à une personne")
      |> refute_has("#pending-actions")
      |> capture(
        "engagement-03-member-next-step.png",
        Enum.at(@scenarios, 1),
        "A member-recorded learning action still changes the suggested next step after refresh"
      )

      _admin = member |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

      browser
      |> visit("/admin/metrics")
      |> assert_has("#metric-actions")
      |> assert_has("#metrics-by-type")
      |> capture(
        "engagement-04-admin-metrics.png",
        Enum.at(@scenarios, 3),
        "The superadmin sees aggregate movement progress from first-party database records"
      )

      Enum.each(@scenarios, &AtddEvidence.mark_scenario_success!/1)
      AtddEvidence.finalize!()
    end

    defp capture(conn, filename, scenario, description) do
      conn = BrowserScreenshot.capture(conn, filename, &PhoenixTest.Playwright.screenshot/2)

      AtddEvidence.record_step(filename, scenario.title, description, %{
        "scenario_id" => scenario.id,
        "scenario" => scenario.title,
        "step" => "1/1",
        "current_url" => "browser",
        "language" => scenario.language,
        "device" => scenario.device,
        "user" => hd(scenario.roles),
        "click_target" => "-"
      })

      conn
    end
  end
end
