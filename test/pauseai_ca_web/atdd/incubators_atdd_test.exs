if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.IncubatorsTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Incubators, Repo, Volunteers}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @moduletag accept_dialogs: true
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "JOIN-PAI-01-#{locale}",
                    title: "Local group admission · #{language}",
                    tags: ["incubators", "membership"],
                    roles: ["Applicant", "Group manager", "Outsider"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("JOIN-PAI-01 · account-linked manual admission", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "JOIN-PAI-01 applicant and manager journey #{locale}", c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      admin =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()
        |> Accounts.Scope.for_user()

      manager = named_user("Synthetic manager")
      applicant = named_user("Synthetic applicant")
      outsider = named_user("Synthetic outsider")
      manager_scope = Accounts.Scope.for_user(manager)
      applicant_scope = Accounts.Scope.for_user(applicant)
      {:ok, group} = Volunteers.create_group(admin, %{name: "Synthetic local group"})
      {:ok, _} = Volunteers.assign_manager(admin, group.id, manager.email)

      {:ok, _} =
        Incubators.configure(admin, group.id, %{
          "name_en" => "Synthetic local group",
          "name_fr" => "Groupe local de démonstration",
          "fsas" => "H2X",
          "published" => true,
          "whatsapp_enabled" => true,
          "whatsapp_approval_confirmed" => true,
          "moderator_contact" => "manager@example.org",
          "whatsapp_invite_url" => "https://chat.whatsapp.com/synthetic-local-review"
        })

      baseline = counts()
      manage_path = "/manage/groups?group=#{group.id}&locale=#{locale}"
      own_path = "/groups/#{group.id}/join?locale=#{locale}"

      b =
        c.conn
        |> login(manager)
        |> visit("/#{locale}")
        |> PhoenixTest.Playwright.click("#account-menu summary")
        |> capture(
          locale,
          "Manager account menu: preceding screen",
          "Click Local groups in the Management section of the account menu"
        )
        |> click_link(
          "#account-management-links [data-navigation-item='pauseai.groups']",
          tr(locale, "Local groups"), exact: true)
        |> connected()
        |> capture(
          locale,
          "Manager opens group configuration",
          "Edit the localized description, then click Save configuration"
        )
        |> fill_in(
          tr(locale, if(locale == "fr", do: "French description", else: "English description")),
          with: "Synthetic local activities"
        )
        |> click_button(tr(locale, "Save configuration"))
        |> assert_has("#flash-info",
          text: tr(locale, "Group configuration saved."),
          exact: false
        )

      b =
        b
        |> switch_browser_identity(&login(&1, applicant))
        |> visit("/#{locale}")
        |> PhoenixTest.Playwright.click("#involvement-menu summary")
        |> capture(
          locale,
          "Applicant involvement menu: preceding screen",
          "Click Local groups in Get involved"
        )
        |> click_link("#act-local-groups", tr(locale, "Local groups"), exact: true)
        |> connected()
        |> assert_has("#group-#{group.id}", text: "Synthetic local activities")
        |> refute_has("a[href='https://chat.whatsapp.com/synthetic-local-review']")
        |> capture(locale, "Applicant opens the public directory", "Click Request to join")
        |> click_link(tr(locale, "Request to join"))
        |> connected()
        |> assert_has("input[name='application[display_name]']", value: "Synthetic applicant")
        |> fill_in(tr(locale, "Your WhatsApp identifier"), with: "+15555550123")
        |> check(tr(locale, "I agree to follow these conduct rules."))
        |> click_button(tr(locale, "Save request"))
        |> assert_has("#my-membership", text: tr(locale, "Pending review"), exact: false)
        |> capture(
          locale,
          "Applicant saves the request",
          "Create a private one-time reference and send it privately to the manager"
        )
        |> click_button(tr(locale, "Create private matching reference"))
        |> assert_has("#matching-reference strong")

      PhoenixTest.Playwright.evaluate(
        b,
        "document.querySelector('#matching-reference strong').textContent.trim()",
        &Process.put(:incubator_reference, &1)
      )

      reference = Process.get(:incubator_reference)
      assert is_binary(reference) and byte_size(reference) > 10
      {:ok, membership} = Incubators.mine(applicant_scope, group.id)

      b =
        b
        |> switch_browser_identity(&login(&1, manager))
        |> visit(manage_path)
        |> connected()
        |> refute_has("#incubator-activity", text: reference, exact: false)
        |> fill_in(tr(locale, "Reference received privately from this applicant"),
          with: reference
        )
        |> click_button(tr(locale, "Match identifier"))
        |> assert_has("#membership-#{membership.id}",
          text: tr(locale, "Identifier matched"),
          exact: false
        )
        |> refute_has("#incubator-activity", text: reference, exact: false)
        |> capture(
          locale,
          "Manager matches the privately received reference",
          "Click Approve request; the website grants no automatic external admission"
        )
        |> click_button(tr(locale, "Approve request"))
        |> assert_has("#membership-#{membership.id}[data-status='approved']")
        |> check(tr(locale, "I verified this member's admission in the external group."))
        |> click_button(tr(locale, "Confirm admission"))
        |> assert_has("#membership-#{membership.id}[data-status='admitted']")
        |> capture(
          locale,
          "Manager confirms observed admission",
          "Only the applicant can reveal their approved invitation"
        )

      {:ok, %{status: "admitted"}} = Incubators.mine(applicant_scope, group.id)
      {:ok, events} = Incubators.activity(manager_scope, group.id)
      refute Enum.any?(events, &(Jason.encode!(&1.details) =~ reference))

      b =
        b
        |> switch_browser_identity(&login(&1, applicant))
        |> visit(own_path)
        |> connected()
        |> refute_has("a[href='https://chat.whatsapp.com/synthetic-local-review']")
        |> click_button(tr(locale, "Show my invitation"))
        |> assert_has("a[href='https://chat.whatsapp.com/synthetic-local-review']")
        |> capture(
          locale,
          "Applicant reveals their own approved synthetic invitation",
          "Withdraw request; no external website is opened"
        )
        |> click_button(tr(locale, "Withdraw request"))
        |> assert_has("#my-membership", text: tr(locale, "Withdrawn"), exact: false)
        |> refute_has("a[href='https://chat.whatsapp.com/synthetic-local-review']")
        |> assert_has("#my-membership",
          text: tr(locale, "External removal is awaiting manager confirmation."),
          exact: false
        )

      b =
        b
        |> switch_browser_identity(&login(&1, manager))
        |> visit(manage_path)
        |> connected()
        |> capture(
          locale,
          "Manager sees external removal pending",
          "Click Confirm external removal after the manual external check"
        )
        |> click_button(tr(locale, "Confirm external removal"))
        |> assert_has("#incubator-activity",
          text: tr(locale, "External removal confirmed"),
          exact: false
        )
        |> refute_has("#incubator-activity", text: reference, exact: false)

      assert {:ok, %{status: "withdrawn", external_removal_pending: false}} =
               Incubators.mine(applicant_scope, group.id)

      b =
        b
        |> switch_browser_identity(&login(&1, outsider))
        |> visit(manage_path)
        |> connected()
        |> refute_has("#incubator-roster")
        |> refute_has("input[name='profile[whatsapp_invite_url]']")
        |> refute_has("#matching-reference")
        |> capture(
          locale,
          "An unrelated account opens the management URL",
          "No roster, reference or private invitation is disclosed"
        )

      PhoenixTest.Playwright.evaluate(
        b,
        "document.documentElement.scrollWidth <= window.innerWidth",
        &assert(&1)
      )

      assert counts() == baseline

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "JOIN-PAI-01-#{locale}"))
      )

      b
    end

    defp named_user(name),
      do: user_fixture() |> Ecto.Changeset.change(name: name) |> Repo.update!()

    defp login(browser, user) do
      {token, _} = generate_user_magic_link_token(user)

      browser
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp connected(browser), do: assert_has(browser, "[data-phx-main].phx-connected")

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp counts,
      do:
        {Repo.aggregate(Accounts.User, :count),
         Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count),
         Repo.aggregate(Volunteers.Manager, :count),
         Repo.aggregate(PauseAiCa.Newsletters.Batch, :count)}

    defp capture(browser, locale, trigger, outcome) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= window.innerWidth",
        &assert(&1)
      )

      id = "JOIN-PAI-01-#{locale}"
      step = Process.get({:incubator_step, locale}, 0) + 1
      Process.put({:incubator_step, locale}, step)
      filename = "#{id}-#{step}.png"

      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:incubator_capture_url, &1)
      )

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "control" => trigger,
        "url" => AtddEvidence.safe_url(Process.get(:incubator_capture_url)),
        "external_systems" =>
          "Synthetic local accounts and configured group; no WhatsApp operation or external sending"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, trigger, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        trigger,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
