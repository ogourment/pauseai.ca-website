if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.ProfileUXTest do
    use AcceptanceHarness.Playwright.Case, async: false

    import PauseAiCa.AccountsFixtures

    alias PauseAiCa.{Accounts, Incubators, Repo, Volunteers}
    alias PauseAiCa.Accounts.Scope
    alias PauseAiCaWeb.{AtddEvidence, AtddNavigation}

    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "PROFILE-UX-01-#{locale}",
                    title:
                      "A member saves location and volunteer contributions independently of MP lookup",
                    tags: ["profiles", "membership"],
                    roles: ["Member", "Group manager", "Unrelated member"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("PROFILE-UX-01 · Personal and volunteer profiles", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      previous = Application.fetch_env!(:pauseai_ca, :represent_req_options)
      test_pid = self()

      Application.put_env(:pauseai_ca, :represent_req_options,
        plug: fn request ->
          send(test_pid, {:represent_lookup, request.request_path})
          PauseAiCa.RepresentStub.call(request)
        end
      )

      on_exit(fn -> Application.put_env(:pauseai_ca, :represent_req_options, previous) end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "PROFILE-UX-01 location, volunteering, privacy and explicit MP lookup #{locale}", c do
        journey(c.conn, unquote(locale))
      end
    end

    defp journey(browser, locale) do
      member = user_fixture(%{email: "volunteer@example.org"})
      personal = if locale == "fr", do: "/fr/profil", else: "/en/profile"
      volunteer = if locale == "fr", do: "/fr/profil/benevolat", else: "/en/profile/volunteer"
      scope = Scope.for_user(member)

      browser =
        browser
        |> sign_in(member, locale)
        |> AtddNavigation.open_section("account")
        |> assert_has("#account-menu a[href='#{personal}']", text: tr(locale, "My profile"))
        |> assert_has("#account-menu a[href='#{volunteer}']",
          text: tr(locale, "Volunteer profile")
        )
        |> refute_has("#account-menu a[href$='/groups'], #account-menu a[href$='/groupes']")
        |> evaluate(
          "document.querySelector('#account-menu > .section-menu-panel').getBoundingClientRect().width >= 200",
          &assert(&1)
        )
        |> capture(locale, "Open the account menu", "Both profiles have direct links.")
        |> click("#account-menu a[href='#{volunteer}']")
        |> assert_path(volunteer)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_profile_breadcrumb(locale, "Volunteer profile")
        |> assert_has("#volunteer-location-reminder a[href='#{personal}#location']")
        |> assert_has("html[lang='#{locale}']")
        |> capture(
          locale,
          "Open Volunteer profile",
          "A new member can start and sees a location reminder."
        )
        |> press("#volunteer-location-reminder a", "Enter")
        |> assert_path(personal)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_profile_breadcrumb(locale, "My profile")
        |> assert_has("#location:focus")
        |> assert_has("#location #profile_postal_code")
        |> evaluate("location.hash", &assert(&1 == "#location"))
        |> fill_in("#profile-form #profile_postal_code", tr(locale, "Postal code (optional)"),
          with: "H2W",
          exact: false
        )
        |> click_button("#profile-form button", tr(locale, "Save changes"))
        |> assert_has("#profile-save-status", text: tr(locale, "Profile saved."), exact: true)
        |> capture(
          locale,
          "Save H2W from the location reminder",
          "The postal area is saved without MP lookup or email opt-in."
        )
        |> visit(personal)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_profile_breadcrumb(locale, "My profile")
        |> assert_has("#profile_postal_code[value='H2W']")
        |> refute_has("#profile-form input[name='profile[local_updates]']:checked")
        |> refute_has("#mp-result")

      member_after_location = Accounts.get_user!(member.id)
      assert member_after_location.fsa == "H2W"
      assert is_nil(member_after_location.postal_code)
      refute member_after_location.local_updates
      refute_received {:represent_lookup, _}

      browser =
        browser
        |> click("#volunteer-profile-link")
        |> assert_path(volunteer)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_profile_breadcrumb(locale, "Volunteer profile")
        |> refute_has("#volunteer-location-reminder")
        |> click("#profile-activities-creative > summary")
        |> click("input[name='profile[selected_skills][]'][value='translation']")
        |> assert_has("input[data-experience='translation'][value='done']")
        |> fill_in("#profile_availability_hours_per_week", tr(locale, "Hours available per week"),
          with: "3"
        )
        |> assert_has("#volunteer-save-status", text: tr(locale, "Unsaved changes"), exact: true)
        |> visit(volunteer)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_profile_breadcrumb(locale, "Volunteer profile")
        |> assert_has("#profile_availability_hours_per_week[value='3']")
        |> assert_has("input[name='profile[selected_skills][]'][value='translation']:checked")

      refute Volunteers.get_profile(scope).id

      browser =
        browser
        |> click_button("#volunteer-profile-form button", tr(locale, "Save changes"))
        |> assert_has("#volunteer-save-status", text: tr(locale, "Saved"), exact: true)
        |> visit(volunteer)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#profile_availability_hours_per_week[value='3']")
        |> assert_has("input[name='profile[selected_skills][]'][value='translation']:checked")
        |> assert_has("input[data-experience='translation'][value='']:checked")
        |> refute_has("#profile_share_contribution:checked")
        |> capture(
          locale,
          "Save translation and three hours, then reload",
          "Experience is optional. Sharing remains off."
        )

      profile = Volunteers.get_profile(scope)
      assert profile.details["availability_hours_per_week"] == 3
      assert profile.details["selected_skills"] == ["translation"]
      refute profile.details["share_contribution"]

      refute Repo.get_by(Incubators.Membership, user_id: member.id)
      refute Repo.get_by(Volunteers.Manager, user_id: member.id)
      refute Repo.get_by(PauseAiCa.Newsletters.Subscription, email: member.email)

      {manager, membership} = group_membership(member)
      manage_path = "/manage/groups?group=#{membership.group_id}&locale=#{locale}"
      contribution = "#member-contribution-#{membership.id}"
      roster_member = "#membership-#{membership.id}"

      browser =
        browser
        |> switch_browser_identity(&sign_in(&1, manager, locale))
        |> open_group_roster()
        |> assert_has(roster_member)
        |> refute_has(contribution)
        |> switch_browser_identity(&sign_in(&1, member, locale))
        |> AtddNavigation.open_section("account")
        |> click("#account-menu a[href='#{volunteer}']")
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#profile-activities-creative[open]")
        |> click("input[data-experience='translation'][value='done']")
        |> click("#profile_share_contribution")
        |> click("#volunteer-additional-skills > summary")
        |> fill_in("#profile_other_skills", tr(locale, "Other skills"),
          with: "Private review availability"
        )
        |> fill_in("#profile_availability_hours_per_week", tr(locale, "Hours available per week"),
          with: "4"
        )
        |> click_button("#volunteer-profile-form button", tr(locale, "Save changes"))
        |> assert_has("#volunteer-save-status", text: tr(locale, "Saved"), exact: true)
        |> visit(volunteer)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#profile_availability_hours_per_week[value='4']")
        |> assert_has("input[data-experience='translation'][value='done']:checked")
        |> assert_has("#profile_share_contribution:checked")
        |> capture(
          locale,
          "Share the contribution and reload",
          "The member sees the saved experience, hours and sharing choice."
        )

      shared = Volunteers.get_profile(scope)
      assert shared.details["share_contribution"]
      assert shared.details["availability_hours_per_week"] == 4
      assert shared.details["experience"]["translation"] == "done"
      assert shared.details["other_skills"] == "Private review availability"

      outsider = user_fixture(%{email: "other-member@example.org"})

      browser
      |> switch_browser_identity(&sign_in(&1, manager, locale))
      |> open_group_roster()
      |> assert_has(contribution, text: tr(locale, "Translation"))
      |> assert_has(contribution <> " dd", text: "4", exact: true)
      |> refute_has(roster_member, text: "Private review availability")
      |> capture(
        locale,
        "Open the group roster as its manager",
        "Only shared activities, experience and hours are visible."
      )
      |> switch_browser_identity(&sign_in(&1, outsider, locale))
      |> AtddNavigation.open_section("account")
      |> click("#account-menu a[href='#{volunteer}']")
      |> assert_path(volunteer)
      |> assert_has("[data-phx-main].phx-connected")
      |> refute_has("#profile_availability_hours_per_week[value='4']")
      |> refute_has("input[name='profile[selected_skills][]'][value='translation']:checked")
      |> refute_has("#profile_share_contribution:checked")
      |> visit(manage_path)
      |> refute_has(contribution)
      |> refute_has("#incubator-roster")
      |> switch_browser_identity(&sign_in(&1, member, locale))
      |> mp_journey(locale, personal, member.id)

      scenario = Enum.find(@scenarios, &(&1.id == "PROFILE-UX-01-#{locale}"))
      AtddEvidence.mark_scenario_success!(scenario)
      AcceptanceHarness.Evidence.record_current_scenario_runtime(scenario)
    end

    defp mp_journey(browser, locale, personal, member_id) do
      browser =
        browser
        |> AtddNavigation.open_section("account")
        |> click("#account-menu a[href='#{personal}']")
        |> assert_path(personal)
        |> assert_has("[data-phx-main].phx-connected")
        |> click("#mp-lookup > summary")
        |> fill_in("#mp-form input[name='lookup[postal_code]']", tr(locale, "Full postal code"),
          with: "H2W"
        )
        |> click_button("#mp-form button", tr(locale, "Look up my MP"))
        |> assert_has("#mp-form", text: tr(locale, "Enter a complete Canadian postal code."))

      refute_received {:represent_lookup, _}

      browser =
        browser
        |> fill_in("#profile-form #profile_postal_code", tr(locale, "Postal code (optional)"),
          with: "H2X 1Y4",
          exact: false
        )
        |> click_button("#profile-form button", tr(locale, "Save changes"))
        |> assert_has("#profile-save-status", text: tr(locale, "Profile saved."), exact: true)
        |> visit(personal)
        |> assert_has("[data-phx-main].phx-connected")
        |> refute_has("#mp-result")
        |> click("#mp-lookup > summary")
        |> assert_has("#mp-form")

      refute_received {:represent_lookup, _}

      browser =
        browser
        |> fill_in("#mp-form input[name='lookup[postal_code]']", tr(locale, "Full postal code"),
          with: "X0A 0H0"
        )
        |> click_button("#mp-form button", tr(locale, "Look up my MP"))
        |> assert_has("#mp-form",
          text: tr(locale, "No federal MP was found for that postal code.")
        )

      assert_received {:represent_lookup, "/postcodes/X0A0H0/"}

      browser =
        browser
        |> fill_in("#mp-form input[name='lookup[postal_code]']", tr(locale, "Full postal code"),
          with: "H2X 1Y4",
          exact: false
        )
        |> click_button("#mp-form button", tr(locale, "Look up my MP"))
        |> assert_has("#mp-result", text: "Steven Guilbeault")
        |> visit(personal)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#mp-result", text: "Steven Guilbeault")
        |> capture(
          locale,
          "Look up a federal MP",
          "An explicit lookup sends the full postal code to the local Represent fixture."
        )

      assert_received {:represent_lookup, "/postcodes/H2X1Y4/"}
      assert Accounts.get_user!(member_id).representative["name"] == "Steven Guilbeault"

      browser
      |> fill_in("#profile-form #profile_postal_code", tr(locale, "Postal code (optional)"),
        with: "H2W",
        exact: false
      )
      |> click_button("#profile-form button", tr(locale, "Save changes"))
      |> assert_has("#profile-save-status", text: tr(locale, "Profile saved."), exact: true)
      |> visit(personal)
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#profile_postal_code[value='H2W']")
      |> refute_has("#mp-result")

      assert is_nil(Accounts.get_user!(member_id).representative)
      refute_received {:represent_lookup, _}
    end

    defp group_membership(member) do
      admin =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()
        |> Scope.for_user()

      manager = user_fixture(%{email: "group-manager@example.org"})
      {:ok, group} = Volunteers.create_group(admin, %{"name" => "Synthetic local group"})
      {:ok, _} = Volunteers.assign_manager(admin, group.id, manager.email)
      {:ok, membership} = Incubators.add_existing_member(admin, group.id, member.email, "member")
      {manager, membership}
    end

    defp open_group_roster(browser) do
      browser
      |> AtddNavigation.open_section("manage")
      |> click("#manage-menu [data-navigation-item='pauseai.groups']")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#incubator-roster")
    end

    defp assert_profile_breadcrumb(browser, locale, title) do
      dashboard = if locale == "fr", do: "/fr/tableau-de-bord", else: "/en/dashboard"
      breadcrumb = "#journey-breadcrumbs[aria-label='#{tr(locale, "Breadcrumbs")}']"

      browser
      |> assert_has("#{breadcrumb} li:first-child a[href='#{dashboard}']",
        text: tr(locale, "My account"),
        exact: true
      )
      |> assert_has("#{breadcrumb} li:nth-child(2):last-child [aria-current='page']",
        text: tr(locale, title),
        exact: true
      )
    end

    defp sign_in(browser, user, locale) do
      {token, _} = generate_user_magic_link_token(user)

      browser
      |> visit("/users/log-in/#{token}?locale=en")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
      |> visit("/#{locale}")
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, locale, control, outcome) do
      evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      step = Process.get(:profile_ux_step, 0) + 1
      Process.put(:profile_ux_step, step)
      evaluate(browser, "location.href", &Process.put(:profile_ux_url, &1))
      url = AtddEvidence.safe_url(Process.get(:profile_ux_url))
      filename = "PROFILE-UX-01-#{locale}-#{step}.png"
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(filename, control, outcome, %{
        "scenario_id" => "PROFILE-UX-01-#{locale}",
        "url" => url,
        "control" => control,
        "step" => step,
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser)),
        "external_systems" =>
          "Isolated local accounts. Represent uses the test fixture; no provider receives private data."
      })

      browser
    end
  end
end
