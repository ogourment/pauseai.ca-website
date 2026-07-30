if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.PublicPrototypeTest do
    use PhoenixTest.Playwright.Case, async: false

    alias AcceptanceHarness.BrowserScreenshot
    alias PauseAiCaWeb.AtddEvidence

    @moduletag :atdd

    @scenario %{
      id: "public-prototype-orients-visitor",
      title: "A visitor opens the bilingual PauseAI Canada prototype",
      roles: ["Visitor"],
      language: "English",
      device: "Desktop",
      source_file: "test/pauseai_ca_web/atdd/public_prototype_atdd_test.exs"
    }

    test "visitor sees the organizing prototype", %{conn: conn} do
      AtddEvidence.reset!(
        "PauseAI Canada acceptance evidence",
        [@scenario],
        %{browser: "Chromium", platform: "GitHub Actions", viewport: "Desktop"}
      )

      conn =
        conn
        |> visit("/")
        |> assert_has("#questions")
        |> assert_has("h1", text: "How far should we let AI advance?")
        |> BrowserScreenshot.capture(
          "public-prototype-01-home.png",
          &PhoenixTest.Playwright.screenshot/2
        )

      AtddEvidence.record_step(
        "public-prototype-01-home.png",
        "The public prototype explains the organizing question",
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
