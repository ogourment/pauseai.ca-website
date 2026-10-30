if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.CampaignCountdownTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Donations.Pages, Repo}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"},
                      {"fr-tablet", "French", "Tablet"}
                    ] do
                  %{
                    id: "CAMPAIGN-COUNTDOWN-01-#{locale}",
                    title: "Campaign banner and donation countdown · #{language}",
                    tags: ["donations", "countdown"],
                    roles: ["Visitor"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)
    setup_all do
      AtddEvidence.reset!("CAMPAIGN-COUNTDOWN-01", @scenarios, %{
        browser: "Chromium",
        viewport: "English desktop and French phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {key, locale, width, height} <- [
          {"en", "en", 1280, 900},
          {"fr", "fr", 390, 844},
          {"fr-tablet", "fr", 768, 1024}
        ] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CAMPAIGN-COUNTDOWN-01 shared timer and expiry #{key}", c do
        locale = unquote(locale)
        scenario = "CAMPAIGN-COUNTDOWN-01-#{unquote(key)}"
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        scope = Accounts.Scope.for_user(admin)
        {:ok, page} = Pages.get_or_create(scope)

        payload =
          put_in(
            page.payload,
            ["campaign", "closes_at"],
            DateTime.utc_now()
            |> DateTime.add(2 * 86_400)
            |> DateTime.truncate(:second)
            |> DateTime.to_iso8601()
          )

        {:ok, page} = Pages.save(scope, page, payload)
        {:ok, _} = Pages.publish(scope, page)

        browser =
          c.conn
          |> visit("/#{locale}")
          |> refute_has("#montreal-protest-banner")
          |> assert_has("#menu-countdown [data-countdown-digits]:not([hidden])")
          |> capture(
            scenario,
            "Campaign replaces the recap",
            "Open the public home page; synthetic deadline is within the final seven days"
          )
          |> PhoenixTest.Playwright.evaluate(
            "[...document.querySelectorAll('#menu-countdown [data-countdown-part]:not([hidden])')].map(e=>e.dataset.countdownPart)",
            &assert(&1 == ["days", "hours"])
          )
          |> PhoenixTest.Playwright.evaluate(
            "document.querySelector('#menu-countdown [data-countdown-unit=hours]').textContent.trim()",
            &Process.put(:menu_hours_before, &1)
          )
          |> PhoenixTest.Playwright.evaluate(
            "(() => { const base=performance.now.bind(performance); Object.defineProperty(performance,'now',{value:()=>base()+3600000,configurable:true}); return true })()",
            &assert(&1)
          )
          |> refute_has("#menu-countdown [data-countdown-unit=hours]",
            text: Process.get(:menu_hours_before)
          )
          |> click("#donate-link")
          |> assert_path(if(locale == "fr", do: "/fr/faire-un-don", else: "/en/donate"))
          |> assert_has("#donation-countdown [data-countdown-unit=seconds]")
          |> capture(
            scenario,
            "Larger donation-page timer",
            "Click Donate in the main menu; compact timer remains inside that menu control"
          )

        browser =
          browser
          |> PhoenixTest.Playwright.evaluate(
            "(() => { const p=document.querySelector('#donation-countdown-panel').getBoundingClientRect();const c=document.querySelector('#donation-campaign-copy').getBoundingClientRect();return p.height<210 && (innerWidth<768 || p.left>=c.right) })()",
            &assert(&1)
          )
          |> PhoenixTest.Playwright.evaluate(
            "(() => { const base=performance.now.bind(performance); Object.defineProperty(performance,'now',{value:()=>base()+1.5*86400000,configurable:true});return true })()",
            &assert(&1)
          )
          |> assert_has("#menu-countdown [data-countdown-part=minutes]:not([hidden])")
          |> refute_has("#menu-countdown [data-countdown-part=days]:not([hidden])")

        browser
        |> PhoenixTest.Playwright.evaluate(
          """
          (() => { const base = performance.now.bind(performance); Object.defineProperty(performance, 'now', {value: () => base() + 3 * 86400000, configurable: true}); return true })()
          """,
          &assert(&1)
        )
        |> assert_has("#donation-countdown [data-countdown-ended]:not([hidden])")
        |> PhoenixTest.Playwright.evaluate(
          "document.querySelector('#fundraising-campaign-banner').hidden",
          &assert(&1)
        )
        |> capture(
          scenario,
          "Deadline expires without reset",
          "Advance only this isolated browser's monotonic clock beyond the deadline"
        )
      end
    end

    defp snapshot(browser) do
      PhoenixTest.Playwright.evaluate(
        browser,
        """
        (() => { const d = document.documentElement.cloneNode(true);
          d.querySelectorAll('script,meta[name="csrf-token"],input[type="hidden"],input[type="password"]').forEach(x=>x.remove());
          d.querySelectorAll('*').forEach(x=>{for(const a of [...x.attributes])if(a.name.startsWith('phx-')||a.name.startsWith('data-phx-')||a.name.startsWith('on'))x.removeAttribute(a.name)});
          d.querySelectorAll('input,textarea,select,button').forEach(x=>x.disabled=true);
          d.querySelectorAll('form').forEach(x=>{x.removeAttribute('action');x.setAttribute('onsubmit','return false')});
          d.querySelectorAll('a').forEach(x=>{x.dataset.originalHref=x.getAttribute('href')||'';x.href='#';x.setAttribute('onclick','return false')});
          d.querySelectorAll('link[rel="stylesheet"]').forEach(x=>x.href=new URL(x.getAttribute('href'),location.href).href);
          d.querySelectorAll('img').forEach(x=>{if(x.getAttribute('src'))x.src=new URL(x.getAttribute('src'),location.href).href});
          return '<!doctype html>'+d.outerHTML; })()
        """,
        &Process.put(:campaign_countdown_snapshot, &1)
      )

      Process.get(:campaign_countdown_snapshot) |> AtddEvidence.scrub_html()
    end

    defp capture(browser, scenario, title, control) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:campaign_countdown_url, &1)
      )

      url = AtddEvidence.safe_url(Process.get(:campaign_countdown_url))
      IO.puts("Capture URL: #{url}; preceding control: #{control}")

      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth && [...document.querySelectorAll('.crm-surface[data-breadcrumb-label]')].every(el => el.scrollWidth <= el.clientWidth)",
        &assert(&1)
      )

      step = Process.get({:campaign_countdown_step, scenario}, 0) + 1
      Process.put({:campaign_countdown_step, scenario}, step)
      filename = "#{scenario}-#{step}.png"

      metadata = %{
        "scenario_id" => scenario,
        "step" => step,
        "url" => url,
        "control" => control,
        "source" =>
          "Actual isolated browser; synthetic CMS deadline for countdown boundary verification; no provider calls or sends"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, title, control, metadata)
      browser = AtddEvidence.capture_full_page(browser, filename)
      html = snapshot(browser)
      File.write!(Path.join("tmp/atdd/screenshots", filename <> ".html"), html)
      AtddEvidence.record_step(filename, title, control, Map.put(metadata, "page_html", html))
      browser
    end
  end
end
