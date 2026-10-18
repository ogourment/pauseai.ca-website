if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.PublicSiteTest do
    use AcceptanceHarness.Playwright.Case, async: false

    alias AcceptanceHarness.BrowserScreenshot
    alias PauseAiCaWeb.AtddEvidence

    @moduletag :atdd

    @scenario %{
      id: "public-site-orients-visitor",
      title: "A visitor opens the bilingual PauseAI Canada website",
      roles: ["Visitor"],
      language: "English",
      device: "Desktop",
      source_file: "test/pauseai_ca_web/atdd/public_site_atdd_test.exs"
    }

    test "visitor sees the organizing website", %{conn: conn} do
      AtddEvidence.reset!(
        "PauseAI Canada acceptance evidence",
        [@scenario],
        %{browser: "Chromium", platform: "GitHub Actions", viewport: "Desktop"}
      )

      conn =
        conn
        |> visit("/")
        |> assert_has("#questions")
        |> refute_has("#warning-shot-banner")
        |> refute_has("#campaign-prompt")
        |> refute_has("[data-learning-root]")
        |> assert_has("#resource-grid .resource-card", count: 4)
        |> click_button("Show my suggested path")
        |> assert_has("#resource-risk.is-recommended")
        |> assert_has("h1", text: "Where do you stand today?")
        |> BrowserScreenshot.capture(
          "public-site-01-home.png",
          &PhoenixTest.Playwright.screenshot/2
        )

      AtddEvidence.record_step(
        "public-site-01-home.png",
        "The public website explains the organizing question",
        "A visitor receives the English landing page, can switch to French, and can begin the private browser-only reflection.",
        %{
          "scenario_id" => @scenario.id,
          "scenario" => @scenario.title,
          "step" => "1/1",
          "current_url" => "/",
          "language" => "English",
          "device" => "Desktop",
          "user" => "Visitor",
          "click_target" => "-"
        }
      )

      AtddEvidence.mark_scenario_success!(@scenario)
      AtddEvidence.finalize!()
      conn
    end
  end
end
