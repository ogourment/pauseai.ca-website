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
      captured =
        BrowserScreenshot.capture(
          conn,
          filename,
          &PhoenixTest.Playwright.screenshot(&1, &2, full_page: true)
        )

      File.write!(
        Path.join("tmp/atdd/screenshots", filename <> ".html"),
        scrub_html(page_html(conn))
      )

      PhoenixTest.Playwright.evaluate(
        conn,
        """
        ({width:document.documentElement.scrollWidth,height:document.documentElement.scrollHeight,
          boxes:[...document.querySelectorAll('#account-entry,#account-email-pending,#account-email-error,#save-progress-invitation,#signup-funnel,#mainstream-safety-context,#delivered-email')]
          .filter(el=>el.getBoundingClientRect().height>0).map(el=>{const r=el.getBoundingClientRect();return {selector:'#'+el.id,x:r.x+scrollX,y:r.y+scrollY,width:r.width,height:r.height}})})
        """,
        &Process.put(:evidence_geometry, &1)
      )

      captured
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

  def scrub_html(html) do
    html =
      Regex.replace(
        ~r/<(?:meta|input)\b[^>]*(?:csrf-token|_csrf_token|user\[token\]|user\[flow\])[^>]*>/,
        html,
        fn tag ->
          Regex.replace(~r/(content|value)="[^"]*"/, tag, "\\1=\"REDACTED\"")
        end
      )

    html = Regex.replace(~r/data-phx-(session|static)="[^"]*"/, html, "data-phx-\\1=\"REDACTED\"")

    Regex.replace(
      ~r{https?://[^\s"<>]+/(?:users/log-in/|letters/confirm/)[^\s"<>]+},
      html,
      "[REDACTED OWNERSHIP LINK]"
    )
  end

  def safe_url("data:" <> _), do: "mailbox://captured-test-delivery"

  def safe_url(url) do
    uri = URI.parse(url)
    uri = if String.starts_with?(uri.path || "", "/users/"), do: %{uri | query: nil}, else: uri

    Regex.replace(
      ~r{(/(?:users/log-in|letters/confirm)/)[^?/#]+(?:\?[^#]*)?},
      URI.to_string(uri),
      "\\1[REDACTED OWNERSHIP LINK]"
    )
  end
end
