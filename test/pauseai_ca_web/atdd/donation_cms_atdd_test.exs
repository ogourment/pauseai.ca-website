if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.DonationCmsTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Donations, Newsletters, Repo}
    alias PauseAiCa.Donations.Pages
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "DON-CMS-01-#{locale}",
                    title: "Donation CMS draft and publication · #{language}",
                    tags: ["donation", "cms"],
                    roles: ["Superadmin"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("DON-CMS-01 · donation content lifecycle", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "DON-CMS-01 draft publication #{locale}", context do
        locale = unquote(locale)
        id = "DON-CMS-01-#{locale}"
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        email = admin.email
        assert_receive {:email, %{to: [{_, ^email}]}}, 1_000
        viewer = user_fixture()
        viewer_email = viewer.email
        assert_receive {:email, %{to: [{_, ^viewer_email}]}}, 1_000
        previous_mode = Application.get_env(:pauseai_ca, :manifund_donations_enabled)
        Application.put_env(:pauseai_ca, :manifund_donations_enabled, true)

        on_exit(fn ->
          Application.put_env(:pauseai_ca, :manifund_donations_enabled, previous_mode)
        end)

        scope = Accounts.Scope.for_user(admin)
        {:ok, original} = Pages.get_or_create(scope)
        {:ok, history} = Pages.history(scope)
        original_revision = hd(history)
        baseline = counts()
        {token, _} = generate_user_magic_link_token(admin)

        title =
          if locale == "fr",
            do: "Soutenir les échanges locaux",
            else: "Support local conversations"

        public_path = if locale == "fr", do: "/fr/faire-un-don", else: "/en/donate"

        browser =
          context.conn
          |> visit("/users/log-in/#{token}")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/manage/accounts?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")
          |> capture(id, "Accounts: preceding screen", "Click Donation page in Management")
          |> click_link(tr(locale, "Donation page"))
          |> assert_has("#donation-page-editor")
          |> assert_has("[data-phx-main].phx-connected")
          |> capture(
            id,
            "Donation CMS before editing",
            "Edit Page title in the active language edition, then Save draft"
          )
          |> fill_in("#donation-#{locale}-title", tr(locale, "Page title"), with: title)
          |> assert_has("#donation-save-status", text: tr(locale, "Unsaved changes"))
          |> click_button(tr(locale, "Save draft"))
          |> assert_has("#donation-save-status", text: tr(locale, "Saved"))
          |> capture(
            id,
            "Saved bilingual page draft",
            "Save draft preserves the current public snapshot"
          )

        {:ok, saved_draft} = Pages.get_or_create(scope)
        assert saved_draft.payload["editions"][locale]["title"] == title
        assert Pages.published() == original.published_payload

        browser =
          browser
          |> click_button(tr(locale, "Preview"))
          |> assert_has("#donation-preview", text: title)
          |> PhoenixTest.Playwright.evaluate(
            "(() => {const el=document.querySelector('#donation-cms-preview-gift-attention');if(matchMedia('(prefers-reduced-motion: reduce)').matches)return el.getAnimations().length===0;if(!el.getClientRects().length)return true;const a=el.getAnimations()[0];return !!a && (a.effect.getComputedTiming().iterations===1 && a.effect.getKeyframes().some(k=>(k.transform||'').includes('1.045')))})()",
            &assert(&1)
          )
          |> capture(
            id,
            "Inert draft preview",
            "Preview shows the shared public renderer without tracking or payment actions"
          )
          |> fill_in("#donation-preview-funding", tr(locale, "Illustrative funding (CAD)"),
            with: "8000"
          )

        browser =
          if unquote(width) < 700 do
            browser
            |> click("#donation-cms-preview-mobile-open")
            |> assert_has("#donation-cms-preview-mobile-dialog[open]")
            |> fill_in(
              "#donation-cms-preview-mobile-gift",
              original.payload["editions"][locale]["gift_label"],
              with: "25"
            )
            |> assert_has("#donation-cms-preview-mobile-gift[value='25']")
            |> click("#donation-cms-preview-mobile-dialog [data-simulator-close]")
            |> refute_has("#donation-cms-preview-mobile-dialog[open]")
          else
            fill_in(
              browser,
              "#donation-cms-preview-gift",
              original.payload["editions"][locale]["gift_label"],
              with: "25"
            )
          end

        browser =
          browser
          |> assert_has("#donation-preview-funding[value='8000']")
          |> assert_has("#donation-cms-preview [data-kind='bucket']", count: 3)
          |> capture(
            id,
            "Illustrative remaining-budget preview",
            "Enter synthetic funding above half the Toronto stage budget and a suggested gift; no provider observation is saved"
          )
          |> click_button(tr(locale, "Publish"))
          |> assert_has("#donation-save-status", text: tr(locale, "Published"))
          |> visit(public_path)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("h1", text: title)
          |> assert_has("#manifund-donate")
          |> refute_has("#donation-funding-unknown")
          |> refute_has("#donation-gift-form")
          |> refute_has("#donation-buckets")
          |> capture(
            id,
            "Published synthetic donation page",
            "Publish makes the saved edition visible in the isolated database"
          )

        assert Pages.published()["editions"][locale]["title"] == title

        browser =
          browser
          |> visit("/manage/donations?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")
          |> click("#donation-history summary")
          |> click_button(
            "button[phx-value-id='#{original_revision.id}']",
            tr(locale, "Restore to draft")
          )
          |> assert_has("#donation-save-status", text: tr(locale, "Restored to draft"))
          |> capture(
            id,
            "Historical copy restored to draft",
            "Restore keeps the published copy unchanged until another explicit Publish"
          )

        {:ok, restored} = Pages.get_or_create(scope)
        assert restored.payload == original.payload
        assert restored.published_payload["editions"][locale]["title"] == title
        {viewer_token, _} = generate_user_magic_link_token(viewer)

        browser =
          browser
          |> reset_browser_state()
          |> visit("/users/log-in/#{viewer_token}")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/manage/donations?locale=#{locale}")
          |> refute_has("#donation-page-editor")
          |> capture(
            id,
            "Ordinary account denied the CMS",
            "A confirmed account cannot open the superadmin editor or its draft"
          )

        assert counts() == baseline
        refute_receive {:email, _}
        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
        browser
      end
    end

    defp counts,
      do: %{
        accounts: Repo.aggregate(Accounts.User, :count),
        pledges: Repo.aggregate(Donations.Pledge, :count),
        subscriptions: Repo.aggregate(Newsletters.Subscription, :count),
        batches: Repo.aggregate(Newsletters.Batch, :count),
        deliveries: Repo.aggregate(Newsletters.Delivery, :count)
      }

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, id, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= window.innerWidth",
        &assert(&1)
      )

      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:donation_cms_url, &1)
      )

      step = Process.get({:donation_cms_step, id}, 0) + 1
      Process.put({:donation_cms_step, id}, step)
      filename = "#{id}-#{step}.png"

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "url" => AtddEvidence.safe_url(Process.get(:donation_cms_url)),
        "control" => control,
        "source" =>
          "Actual local CMS/public renderer; synthetic administrator and viewer, isolated rollback database",
        "external_systems" => "No provider request, real payment, account creation or message"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, control, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        control,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
