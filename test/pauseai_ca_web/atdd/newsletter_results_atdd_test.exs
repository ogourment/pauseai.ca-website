if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.NewsletterResultsTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Newsletters, Repo}
    alias PauseAiCa.Newsletters.{Batch, Batches, Delivery, Drafts, ResultSnapshot}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios Enum.map([{"en", "English", "Desktop"}, {"fr", "French", "Phone"}], fn {locale,
                                                                                       language,
                                                                                       device} ->
                 %{
                   id: "PA-NEWS-RESULTS-01-#{locale}",
                   title:
                     "Cached send comparison, saved content and stable detail navigation · #{language}",
                   tags: ["mail", "newsletter", "results"],
                   roles: ["Superadmin"],
                   language: language,
                   device: device,
                   source_file: __ENV__.file
                 }
               end)

    setup_all do
      AtddEvidence.reset!("PA-NEWS-RESULTS-01 · newsletter results", @scenarios, %{
        browser: "Chromium",
        viewport: "English desktop 1280 and French phone 390"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "PA-NEWS-RESULTS-01 cached results and retained navigation #{locale}", c do
        locale = unquote(locale)
        scenario = "PA-NEWS-RESULTS-01-#{locale}"
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

        admin =
          user_fixture(%{email: "results-admin@example.org"})
          |> Ecto.Changeset.change(superadmin: true)
          |> Repo.update!()

        scope = Accounts.Scope.for_user(admin)
        {:ok, signup} = Newsletters.request_signup("results-review@example.org", %{consent: true})
        {:ok, _} = Newsletters.confirm(signup.confirmation_token)
        {:ok, draft} = Drafts.create(scope)

        {:ok, draft} =
          Drafts.save(scope, draft, %{
            "subject" => "Synthetic newsletter · Résultats",
            "source" =>
              "# Saved newsletter · Infolettre\n\n[Event · Événement](https://example.org/event)\n\n[Join Toronto](https://example.org/en/participate?intent=waitlist&city=Toronto)",
            "recipient_mode" => "newsletter",
            "recipient_keys" => [signup.subscription.id]
          })

        {:ok, batch} = Batches.prepare(scope, draft, "newsletter", [signup.subscription.id], true)

        receipt =
          Repo.get_by!(Delivery, batch_id: batch.id)
          |> Ecto.Changeset.change(
            state: "accepted",
            attempted_at: DateTime.utc_now(),
            authorizing_admin_id: admin.id
          )
          |> Repo.update!()

        second = clone_batch(batch, receipt, DateTime.add(batch.inserted_at, -10))
        cache(batch.id, 1)
        cache(second.id, 0)
        baseline = Repo.aggregate(Delivery, :count)
        {token, _} = generate_user_magic_link_token(admin)

        b =
          c.conn
          |> visit("/users/log-in/#{token}")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/#{locale}")
          |> assert_has("#account-menu summary")
          |> PhoenixTest.Playwright.click("#account-menu summary")

        b =
          b
          |> capture(
            scenario,
            "Account menu before opening Emails",
            "Click Emails in the Management section: data-navigation-item=pauseai.mail"
          )
          |> click_link(
            "#account-management-links [data-navigation-item='pauseai.mail']",
            tr(locale, "Emails"),
            exact: true
          )
          |> connected()

        b =
          b
          |> capture(
            scenario,
            "Emails workspace before results",
            "Click Sent & results: data-navigation-item=mail.results"
          )
          |> click_link("[data-navigation-item='mail.results']", tr(locale, "Sent & results"),
            exact: true
          )
          |> connected()
          |> assert_has("#send-#{batch.id} [data-stored-results]",
            text: tr(locale, "Observed clicks")
          )
          |> assert_has("#send-#{batch.id} [data-stored-results] dd", text: "1", exact: true)
          |> assert_has("#send-#{second.id}",
            text:
              tr(
                locale,
                "No deliveries, opens or clicks reported yet. Accepted submissions do not establish delivery or reading."
              )
          )

        b =
          b
          |> capture(
            scenario,
            "Two saved batches with cached outcomes",
            "Click the edition/date link in the first newsletter send row"
          )
          |> PhoenixTest.Playwright.click("#send-#{batch.id} a")
          |> connected()
          |> assert_has("#sent-content-preview iframe[sandbox='']")
          |> assert_has("#clicked-links", text: "https://example.org/event")
          |> assert_has("#clicked-links strong", text: "1", exact: true)

        PhoenixTest.Playwright.evaluate(
          b,
          "(() => {const f=document.querySelector('#sent-content-preview iframe'); return f.srcdoc.includes('<h1>Saved newsletter') && !f.srcdoc.includes('<a ') && f.srcdoc.includes(\"default-src 'none'\")})()",
          &assert(&1)
        )

        b =
          capture(
            b,
            scenario,
            "Saved content and cached authored-link clicks",
            "Next send and Previous send retain the original order after a newer send is inserted"
          )

        newer = clone_batch(batch, receipt, DateTime.add(batch.inserted_at, 10))
        cache(newer.id, 0)

        b =
          b
          |> click_link("a", tr(locale, "Next send"), exact: true)
          |> connected()
          |> assert_path("/manage/mail/results/#{second.id}")
          |> click_link("a", tr(locale, "Previous send"), exact: true)
          |> connected()
          |> assert_path("/manage/mail/results/#{batch.id}")
          |> click_link("a", tr(locale, "Back to results"), exact: true)
          |> connected()
          |> assert_has("#send-#{batch.id}")
          |> assert_has("#send-#{second.id}")
          |> refute_has("#send-#{newer.id}")

        PhoenixTest.Playwright.evaluate(b, "location.hash", &assert(&1 == "#send-#{batch.id}"))

        b =
          capture(
            b,
            scenario,
            "Back restores the original page and send anchor",
            "Back to results; the newly inserted batch is absent from this retained context"
          )

        b =
          b
          |> visit("/manage/mail/results?locale=#{locale}")
          |> connected()
          |> assert_has("#send-#{newer.id}")

        assert Repo.aggregate(Delivery, :count) == baseline + 1
        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == scenario)))
        b
      end
    end

    defp connected(b), do: assert_has(b, "[data-phx-main].phx-connected")

    defp clone_batch(batch, receipt, at) do
      attrs =
        batch
        |> Map.from_struct()
        |> Map.drop([:__meta__, :id])
        |> Map.merge(%{inserted_at: at, preparation_key: :crypto.strong_rand_bytes(32)})

      next = Repo.insert!(struct(Batch, attrs))

      attrs =
        receipt |> Map.from_struct() |> Map.drop([:__meta__, :id]) |> Map.put(:batch_id, next.id)

      Repo.insert!(struct(Delivery, attrs))
      next
    end

    defp cache(id, clicks) do
      Repo.insert!(%ResultSnapshot{
        batch_id: id,
        partial: false,
        refreshed_at: DateTime.utc_now(),
        observed: %{
          "delivered" => clicks,
          "opened" => clicks,
          "proxy_opened" => 0,
          "clicked" => clicks,
          "bounced" => 0,
          "unsubscribed" => 0,
          "links" => %{
            "version" => 1,
            "complete" => true,
            "items" => [
              %{
                "url" => "https://example.org/event",
                "label" => "Event · Événement",
                "clicked" => clicks
              }
            ]
          }
        }
      })
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
        &Process.put(:newsletter_results_snapshot, &1)
      )

      Process.get(:newsletter_results_snapshot) |> AtddEvidence.scrub_html()
    end

    defp capture(browser, scenario, title, control) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:newsletter_results_url, &1)
      )

      url = AtddEvidence.safe_url(Process.get(:newsletter_results_url))
      IO.puts("Capture URL: #{url}; preceding control: #{control}")

      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth && [...document.querySelectorAll('.crm-surface[data-breadcrumb-label]')].every(el => el.scrollWidth <= el.clientWidth)",
        &assert(&1)
      )

      step = Process.get({:newsletter_results_step, scenario}, 0) + 1
      Process.put({:newsletter_results_step, scenario}, step)
      filename = "#{scenario}-#{step}.png"

      metadata = %{
        "scenario_id" => scenario,
        "step" => step,
        "url" => url,
        "control" => control,
        "source" =>
          "Actual isolated browser; synthetic saved send batches and cached link counts; no provider network or sends"
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
