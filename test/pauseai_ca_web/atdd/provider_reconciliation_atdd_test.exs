if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.ProviderReconciliationTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Newsletters, Repo}
    alias PauseAiCa.Newsletters.{ProviderEvent, ProviderSync}
    alias PauseAiCa.ProviderReconciliationFixtures, as: Fixtures
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios Enum.map([{"en", "English", "Desktop"}, {"fr", "French", "Phone"}], fn {locale,
                                                                                       language,
                                                                                       device} ->
                 %{
                   id: "MAIL-RECON-01-#{locale}",
                   title:
                     "Provider reconciliation with five synthetic provider cases and a local withdrawal baseline · #{language}",
                   tags: ["mail", "newsletter", "reconciliation"],
                   roles: ["Superadmin"],
                   language: language,
                   device: device,
                   source_file: __ENV__.file
                 }
               end)

    setup_all do
      AtddEvidence.reset!("MAIL-RECON-01 · automatic deliverability evidence", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "MAIL-RECON-01 exact reconciliation review #{locale}", c do
        locale = unquote(locale)
        scenario = "MAIL-RECON-01-#{locale}"
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

        admin =
          user_fixture(%{email: "reconciliation-admin@example.org"})
          |> Ecto.Changeset.change(superadmin: true)
          |> Repo.update!()

        assert_receive {:email, _}, 1000
        scope = Accounts.Scope.for_user(admin)
        fixture = Fixtures.five_receipts(scope)

        previous =
          Map.new(
            [
              :brevo_api_key,
              :brevo_history_req_options,
              :mail_environment,
              :newsletter_provider_sync_enabled
            ],
            &{&1, Application.get_env(:pauseai_ca, &1)}
          )

        Fixtures.stub_history(fixture.events)
        Application.put_env(:pauseai_ca, :mail_environment, :production)
        Application.put_env(:pauseai_ca, :newsletter_provider_sync_enabled, true)

        on_exit(fn ->
          Enum.each(previous, fn {key, value} ->
            if is_nil(value),
              do: Application.delete_env(:pauseai_ca, key),
              else: Application.put_env(:pauseai_ca, key, value)
          end)
        end)

        {:ok, synced} = ProviderSync.run(fn _ -> {:ok, []} end, fixture.now)
        {token, _} = generate_user_magic_link_token(admin)
        path = "/manage/mail/results/#{fixture.batch.id}?locale=#{locale}"
        audience = "/manage/mail/newsletters?locale=#{locale}"

        browser =
          c.conn
          |> visit("/users/log-in/#{token}")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit(path)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("[data-review='hard-bounce']", text: "0", exact: true)
          |> assert_has(
            "#provider-synchronization time[datetime='#{DateTime.to_iso8601(synced.last_success_at)}']"
          )
          |> capture(
            scenario,
            "Before reconciliation: five provider cases plus local withdrawal",
            "Open Sent & results; Refresh results and recipient status next"
          )
          |> click_button(tr(locale, "Refresh results and recipient status"))
          |> assert_has("[data-review='hard-bounce']", text: "1", exact: true)
          |> assert_has("[data-review='unsubscribe']", text: "1", exact: true)
          |> assert_has("[data-review='soft-bounce']", text: "3", exact: true)
          |> assert_has("[data-review='invalid-domain']", text: "1", exact: true)
          |> click("#newsletter-deliverability summary")
          |> assert_has("#deliverability-review-rows", text: "hard@example.org")
          |> assert_has("#deliverability-review-rows", text: "dns@example.org")
          |> assert_has("#deliverability-review-rows", text: "rbl@example.org")
          |> assert_has("#deliverability-review-rows", text: tr(locale, "Mailbox full"))
          |> capture(
            scenario,
            "After refresh: permanent failure, purpose withdrawal and soft review",
            "Refresh results and recipient status → Review affected recipients"
          )

        assert Repo.aggregate(ProviderEvent, :count) == 5
        refute Newsletters.eligible?(fixture.recipients["hard"].email)
        refute Newsletters.eligible?(fixture.recipients["dns"].email)
        refute Newsletters.eligible?(fixture.recipients["unsubscribe"].email)
        refute Newsletters.eligible?(fixture.recipients["local"].email)
        assert Newsletters.eligible?(fixture.recipients["full"].email)
        assert Newsletters.eligible?(fixture.recipients["rbl"].email)

        browser =
          browser
          |> click_button(tr(locale, "Refresh results and recipient status"))
          |> assert_has("[data-review='hard-bounce']", text: "1", exact: true)

        assert Repo.aggregate(ProviderEvent, :count) == 5

        browser =
          browser
          |> visit(audience)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#newsletter-#{fixture.recipients["hard"].id}",
            text: tr(locale, "Permanent address failure")
          )
          |> assert_has("#newsletter-#{fixture.recipients["dns"].id}",
            text: tr(locale, "Invalid domain: verify the address")
          )
          |> assert_has("#newsletter-#{fixture.recipients["unsubscribe"].id}",
            text: tr(locale, "Withdrawn")
          )
          |> capture(
            scenario,
            "Audience eligibility after reconciliation",
            "Open Newsletter lists; inspect each synthetic recipient's reason"
          )

        {:ok, failed} =
          ProviderSync.run(fn _ -> {:error, :rate_limited} end, DateTime.add(fixture.now, 900))

        assert failed.cursor_at == synced.cursor_at

        browser
        |> visit(path)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#provider-synchronization [role='alert']",
          text:
            tr(
              locale,
              "Provider reconciliation needs attention. Existing address holds and withdrawals remain in effect."
            )
        )
        |> assert_has(
          "#provider-synchronization time[datetime='#{DateTime.to_iso8601(synced.last_success_at)}']"
        )
        |> capture(
          scenario,
          "A failed later poll preserves the prior success date and all holds",
          "Reopen Sent & results after the synthetic provider rate limit"
        )

        refute_receive {:email, _}, 100
        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == scenario)))
      end
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

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
        &Process.put(:provider_reconciliation_snapshot, &1)
      )

      Process.get(:provider_reconciliation_snapshot) |> AtddEvidence.scrub_html()
    end

    defp capture(browser, scenario, title, control) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:provider_reconciliation_url, &1)
      )

      url = AtddEvidence.safe_url(Process.get(:provider_reconciliation_url))
      IO.puts("Capture URL: #{url}; preceding control: #{control}")

      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      step = Process.get({:provider_reconciliation_step, scenario}, 0) + 1
      Process.put({:provider_reconciliation_step, scenario}, step)
      filename = "#{scenario}-#{step}.png"

      metadata = %{
        "scenario_id" => scenario,
        "step" => step,
        "url" => url,
        "control" => control,
        "source" =>
          "Actual isolated browser; five synthetic provider cases plus one local withdrawal at example.org; no provider network or sends"
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
