defmodule PauseAiCaWeb.AtddEvidence do
  @moduledoc false

  alias AcceptanceHarness.{BrowserEvidence, BrowserScreenshot}

  defdelegate reset!(title, scenarios, run_context), to: AcceptanceHarness.Evidence
  defdelegate record_step(name, title, description, metadata), to: AcceptanceHarness.Evidence
  defdelegate record_scenario_runtime(scenario, duration_ms), to: AcceptanceHarness.Evidence
  defdelegate mark_scenario_success!(scenario), to: AcceptanceHarness.Evidence
  defdelegate finalize!(), to: AcceptanceHarness.Evidence

  def capture_full_page(conn, filename) do
    conn =
      PhoenixTest.Playwright.evaluate(
        conn,
        "(#{BrowserEvidence.pin_viewport_chrome_script()})()"
      )

    try do
      BrowserScreenshot.capture(
        conn,
        filename,
        &PhoenixTest.Playwright.screenshot(&1, &2, full_page: true)
      )
    after
      PhoenixTest.Playwright.evaluate(
        conn,
        "(#{BrowserEvidence.unpin_viewport_chrome_script()})()"
      )
    end
  end

  def page_html(conn) do
    {:ok, html} = PlaywrightEx.Frame.content(conn.frame_id, timeout: 8_000)
    html
  end
end
