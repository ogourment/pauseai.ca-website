if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.ManifundDonateTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Donations, Newsletters, Repo, Volunteers}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @url "https://manifund.org/projects/pauseai-canada-national-expansion--core-operations"
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "DON-PAI-01-#{locale}",
                    title: "Proposed Manifund donation handoff · #{language}",
                    tags: ["donation", "proposed"],
                    roles: ["Visitor"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end) ++
                 [
                   %{
                     id: "DON-PAI-01-history",
                     title: "Historical pledge access remains restricted",
                     tags: ["donation", "proposed"],
                     roles: ["Superadmin", "Group manager", "Visitor"],
                     language: "English",
                     device: "Desktop",
                     source_file: __ENV__.file
                   }
                 ]

    setup_all do
      AtddEvidence.reset!("DON-PAI-01 · proposed donation replacement", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      old_enabled = Application.get_env(:pauseai_ca, :manifund_donations_enabled)
      old_campaign = Application.get_env(:pauseai_ca, :manifund_campaign)
      Application.put_env(:pauseai_ca, :manifund_donations_enabled, true)

      on_exit(fn ->
        Application.put_env(:pauseai_ca, :manifund_donations_enabled, old_enabled)
        Application.put_env(:pauseai_ca, :manifund_campaign, old_campaign)
      end)

      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "DON-PAI-01 proposed public handoff #{locale}", c do
        locale = unquote(locale)
        id = "DON-PAI-01-#{locale}"
        baseline = counts()
        path = if locale == "fr", do: "/fr/faire-un-don", else: "/en/donate"

        b =
          c.conn
          |> visit("/#{locale}")
          |> capture(id, "Public home page", "Click Donate in the header")
          |> click_link(tr(locale, "Donate"))
          |> assert_path(path)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#manifund-donate", text: tr(locale, "Donate on Manifund"))
          |> assert_has("#manifund-account-requirement",
            text:
              tr(
                locale,
                "A Manifund account is required to donate. You can read the full proposal without an account."
              )
          )
          |> assert_has(
            "#manifund-donate[href='#{@url}'][target='_blank'][data-donation='manifund']"
          )
          |> assert_has("#manifund-proposal[href='#{@url}']")
          |> assert_has("#donation-email", text: "pauseaicanada@proton.me")
          |> assert_has("#donate-interac strong", text: "PauseAI Canada")
          |> refute_has("#pledge-form")
          |> refute_has("#pledge-suggestions")
          |> capture(
            id,
            "Donate opens the campaign summary",
            "The Manifund handoff requires its account; Interac remains available"
          )

        PhoenixTest.Playwright.evaluate(
          b,
          "document.documentElement.scrollWidth <= window.innerWidth",
          &assert(&1)
        )

        Application.put_env(:pauseai_ca, :manifund_campaign,
          project_id: "invalid",
          url: "https://invalid.example.org"
        )

        b =
          b
          |> visit(path)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#manifund-unavailable")
          |> refute_has("#manifund-donate")
          |> assert_has("#donation-email", text: "pauseaicanada@proton.me")
          |> capture(
            id,
            "Reload with unusable campaign configuration",
            "Local summary and verified Interac details remain readable"
          )

        assert counts() == baseline
        refute_receive {:email, _}
        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
        b
      end
    end

    @tag screenshot: true
    @tag browser_context_opts: [viewport: %{width: 1280, height: 900}]
    test "DON-PAI-01 preserves historical follow-up and manager/visitor denial", c do
      id = "DON-PAI-01-history"

      {:ok, :recorded} =
        Donations.pledge(%{
          "name" => "Historical example",
          "email" => "historical@example.org",
          "locale" => "en",
          "amount_cad" => "125",
          "frequency" => "monthly",
          "notes" => "For printing",
          "contact_consent" => true
        })

      original = Repo.one!(Donations.Pledge)
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      manager = user_fixture()
      scope = Accounts.Scope.for_user(admin)
      {:ok, group} = Volunteers.create_group(scope, %{"name" => "Historical review"})
      {:ok, _} = Volunteers.assign_manager(scope, group.id, manager.email)
      baseline = counts()

      b =
        c.conn
        |> login(admin)
        |> visit("/admin/dashboard?locale=en")
        |> capture(id, "Superadmin dashboard", "Click Donation pledges")
        |> click_link("Donation pledges")
        |> assert_has("#donation-pledges", text: "historical@example.org")
        |> assert_has("#donation-pledges", text: "Monthly")
        |> assert_has("#donation-pledges", text: "For printing")
        |> capture(
          id,
          "Read the historical pledge",
          "Recorded amount, frequency, notes and consent are preserved"
        )

      b =
        switch_browser_identity(b, &login(&1, manager))
        |> visit("/admin/donation-pledges")
        |> assert_has("body", text: "superadmin required")
        |> refute_has("#donation-pledges")
        |> capture(
          id,
          "Group manager opens the restricted URL",
          "Fresh server authorization denies historical pledge details"
        )

      b =
        reset_browser_state(b)
        |> visit("/admin/donation-pledges")
        |> refute_has("#donation-pledges")
        |> capture(
          id,
          "Visitor opens the restricted URL",
          "Authentication is required; no pledge details are disclosed"
        )

      assert Repo.get!(Donations.Pledge, original.id) == original
      assert counts() == baseline
      AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      b
    end

    defp login(b, user) do
      {token, _} = generate_user_magic_link_token(user)

      b
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp counts,
      do: %{
        pledges: Repo.aggregate(Donations.Pledge, :count),
        accounts: Repo.aggregate(Accounts.User, :count),
        subscriptions: Repo.aggregate(Newsletters.Subscription, :count),
        batches: Repo.aggregate(Newsletters.Batch, :count),
        deliveries: Repo.aggregate(Newsletters.Delivery, :count)
      }

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(b, id, control, outcome) do
      step = Process.get({:donation_step, id}, 0) + 1
      Process.put({:donation_step, id}, step)
      filename = "#{id}-#{step}.png"
      PhoenixTest.Playwright.evaluate(b, "location.href", &Process.put(:donation_url, &1))

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "url" => AtddEvidence.safe_url(Process.get(:donation_url)),
        "control" => control,
        "source" =>
          "Actual local proposed UI; synthetic records; no payment/provider/account creation",
        "external_systems" => "No Manifund request; static configured handoff"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, control, outcome, metadata)
      b = AtddEvidence.capture_full_page(b, filename)

      AtddEvidence.record_step(
        filename,
        control,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(b)))
      )

      b
    end
  end
end
