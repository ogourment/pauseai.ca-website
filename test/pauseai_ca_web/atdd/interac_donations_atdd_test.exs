if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.InteracDonationsTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Repo, Newsletters}
    alias PauseAiCa.Accounts.Scope
    alias PauseAiCa.Donations.{Interac, InteracDeclaration, Pages}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "DON-INTERAC-01-#{locale}",
                     title: "Private Interac declaration and bank matching · #{language}",
                     language: language,
                     device: device,
                     roles: ["Visitor", "Superadmin"],
                     tags: ["donation", "interac"],
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!(
        "DON-INTERAC-01 · private declaration and bank verification",
        @scenarios,
        %{browser: "Chromium", viewport: "Desktop and phone"}
      )

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "DON-INTERAC-01 declaration to private bank receipt #{locale}", context do
        locale = unquote(locale)
        scenario_id = "DON-INTERAC-01-#{locale}"
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        assert_receive {:email, _}
        scope = Scope.for_user(admin)
        {:ok, page} = Pages.get_or_create(scope)
        {:ok, _} = Pages.publish(scope, page)

        before = %{
          accounts: Repo.aggregate(Accounts.User, :count),
          subscriptions: Repo.aggregate(Newsletters.Subscription, :count)
        }

        path = if locale == "fr", do: "/fr/faire-un-don", else: "/en/donate"
        email = "interac-#{locale}@example.org"
        anonymous = locale == "en"

        browser =
          context.conn
          |> visit("/#{locale}")
          |> capture(scenario_id, "Public home page", "Click Donate in the header")
          |> click_link(tr(locale, "Donate"))
          |> assert_path(path)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#donate-interac:not([open]) > summary")
          |> refute_has("#interac-declaration-form")
          |> capture(scenario_id, "Interac section starts collapsed", "Open the Interac summary")
          |> click("#donate-interac > summary")
          |> assert_has("#interac-declaration-form")
          |> assert_has("#donation-email", text: "pauseaicanada@proton.me")
          |> assert_anonymous_default()
          |> capture(
            scenario_id,
            "Compact declaration with anonymous default",
            "Enter private matching details and choose the acknowledgement preference"
          )
          |> fill_in(tr(locale, "Name shown on transfer"), with: "Synthetic bank sender")
          |> assert_has("#donate-interac[open]")
          |> fill_in(tr(locale, "Contact email"), with: email)
          |> fill_in(tr(locale, "Amount (CAD)"), with: "25.50")
          |> select(tr(locale, "Anonymous donation"),
            option: tr(locale, if(anonymous, do: "Yes", else: "No"))
          )
          |> capture(
            scenario_id,
            "Anonymous/public acknowledgement choice",
            "Record the declaration; no transfer is performed by the form"
          )
          |> click_button(tr(locale, "Record donation"))
          |> assert_has("#interac-declaration-status",
            text: tr(locale, "Declaration recorded. Awaiting bank verification.")
          )
          |> capture(
            scenario_id,
            "Pending declaration confirmation",
            "Await actual bank matching; no received amount is credited"
          )

        declaration = Repo.one!(InteracDeclaration)
        assert declaration.state == "pending" and declaration.received_minor == nil
        assert declaration.account_ref == nil
        assert declaration.anonymous == anonymous
        assert {:ok, %{received_minor: 0, pending: 1, verified: 0}} = Interac.summary(scope)
        {token, _} = generate_user_magic_link_token(admin)

        browser =
          browser
          |> visit("/users/log-in/#{token}?locale=en")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/admin/interac-donations?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#interac-pending-count", text: "1")
          |> capture(
            scenario_id,
            "Superadmin private matching list",
            "Open the synthetic sender's declaration"
          )
          |> click_link("Synthetic bank sender")
          |> assert_has("#interac-verification-form")
          |> assert_has("body", text: email)
          |> capture(
            scenario_id,
            "Private matching details visible to authorized organizer",
            "Review a simulated bank receipt and explicitly confirm it"
          )
          |> fill_in(tr(locale, "Amount received (CAD)"), with: "25.50")
          |> fill_in(tr(locale, "Date received"), with: Date.to_iso8601(Date.utc_today()))
          |> fill_in(tr(locale, "Bank reference (optional)"),
            with: "SYNTHETIC-#{locale}-RECEIPT-1"
          )
          |> fill_in(tr(locale, "Private verification note (optional)"),
            with: "SYNTHETIC TEST ONLY — no bank request or real transfer"
          )
          |> check(tr(locale, "I checked this deposit in the bank account."))
          |> click_button(tr(locale, "Verify bank receipt"))
          |> assert_has("#interac-verified-receipt", text: tr(locale, "Bank receipt verified"))
          |> assert_has("#interac-received-total",
            text: if(locale == "fr", do: "25,50", else: "25.50")
          )
          |> capture(
            scenario_id,
            "Synthetic receipt verified with actor attribution",
            "Recorded bank verification is separate from public Manifund pending offers"
          )

        verified = Repo.get!(InteracDeclaration, declaration.id)
        assert verified.state == "verified" and verified.received_minor == 2550
        assert verified.verified_actor_id == admin.id

        assert before == %{
                 accounts: Repo.aggregate(Accounts.User, :count),
                 subscriptions: Repo.aggregate(Newsletters.Subscription, :count)
               }

        refute_receive {:email, _}

        browser =
          browser
          |> reset_browser_state()
          |> visit(path)
          |> refute_has("body", text: email)
          |> refute_has("body", text: "Synthetic bank sender")
          |> capture(
            scenario_id,
            "Public page keeps matching identities private",
            "No public donor list or automatic provider-total blending"
          )

        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == scenario_id)))
        browser
      end
    end

    defp assert_anonymous_default(browser) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.querySelector('#interac-declaration-anonymous').value",
        &assert(&1 == "true")
      )

      browser
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, id, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:interac_capture_url, &1)
      )

      url = AtddEvidence.safe_url(Process.get(:interac_capture_url))
      IO.puts("Capture URL: [#{url}](#{url})")
      step = Process.get({:interac_step, id}, 0) + 1
      Process.put({:interac_step, id}, step)
      filename = "#{id}-#{step}.png"

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "url" => url,
        "control" => control,
        "source" =>
          "Actual isolated local application; synthetic declaration, administrator and bank evidence only",
        "external_systems" =>
          "No bank/provider request, real payment, production account/role change or external mail delivery"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, control, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, filename)

      html = captured_html(browser) |> AtddEvidence.scrub_html()
      File.write!(Path.join("tmp/atdd/screenshots", filename <> ".html"), html)
      AtddEvidence.record_step(filename, control, outcome, Map.put(metadata, "page_html", html))
      browser
    end

    defp captured_html(browser) do
      PhoenixTest.Playwright.evaluate(
        browser,
        ~S"""
        (() => {
          const snapshot = document.documentElement.cloneNode(true);
          const originals = [...document.querySelectorAll('input,textarea,select')];
          [...snapshot.querySelectorAll('input,textarea,select')].forEach((copy, index) => {
            const original = originals[index];
            if (copy.tagName === 'TEXTAREA') copy.textContent = original.value;
            else if (copy.tagName === 'SELECT') [...copy.options].forEach((option, i) => {
              if (original.options[i].selected) option.setAttribute('selected', 'selected');
              else option.removeAttribute('selected');
            });
            else {
              copy.setAttribute('value', original.value);
              if (original.checked) copy.setAttribute('checked', 'checked');
              else copy.removeAttribute('checked');
            }
          });
          snapshot.querySelectorAll('script').forEach(node => node.remove());
          snapshot.querySelectorAll('*').forEach(node => [...node.attributes].forEach(attr => {
            if (attr.name.startsWith('on') || attr.name.startsWith('phx-')) node.removeAttribute(attr.name);
          }));
          snapshot.querySelectorAll('form').forEach(form => form.removeAttribute('action'));
          snapshot.querySelectorAll('button,input[type=checkbox],input[type=radio],select').forEach(node => node.disabled = true);
          snapshot.querySelectorAll('input,textarea').forEach(node => node.readOnly = true);
          snapshot.querySelectorAll('a').forEach(node => { node.removeAttribute('href'); node.setAttribute('aria-disabled', 'true'); });
          return '<!doctype html>' + snapshot.outerHTML;
        })()
        """,
        &Process.put(:interac_snapshot_html, &1)
      )

      Process.get(:interac_snapshot_html)
    end
  end
end
