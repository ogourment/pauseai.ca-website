if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.WelcomeCallsTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Incubators, Repo, Welcome, Volunteers}
    alias PauseAiCa.Welcome.{Session, Participant}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "WELCOME-PAI-01-#{locale}",
                    title: "Proposed welcome cohort · #{language}",
                    tags: ["welcome", "proposed"],
                    roles: ["Group manager", "Invited account"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)
    setup_all do
      AtddEvidence.reset!(
        "WELCOME-PAI-01 · selected accounts, draft, RSVP and outcomes",
        @scenarios,
        %{browser: "Chromium", viewport: "Desktop and phone"}
      )

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      old = Application.get_env(:pauseai_ca, :welcome_calls_enabled)
      Application.put_env(:pauseai_ca, :welcome_calls_enabled, true)
      on_exit(fn -> Application.put_env(:pauseai_ca, :welcome_calls_enabled, old) end)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "WELCOME-PAI-01 selected-account journey #{locale}", c do
        locale = unquote(locale)
        id = "WELCOME-PAI-01-#{locale}"
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        admin_scope = Accounts.Scope.for_user(admin)
        {:ok, group} = Volunteers.create_group(admin_scope, %{name: "Synthetic welcome group"})
        manager = user_fixture() |> Ecto.Changeset.change(name: "Alex") |> Repo.update!()
        {:ok, _} = Volunteers.assign_manager(admin_scope, group.id, manager.email)

        person =
          user_fixture()
          |> Ecto.Changeset.change(name: "Camille")
          |> Repo.update!()

        {:ok, _} =
          Incubators.configure(admin_scope, group.id, %{
            "name_en" => "Synthetic welcome group",
            "name_fr" => "Groupe d’accueil synthétique",
            "published" => true
          })

        scope = Accounts.Scope.for_user(manager)
        # Fixture setup emits account-confirmation emails. Consume exactly those
        # messages before asserting that welcome planning sends no email.
        for user <- [admin, manager, person] do
          address = user.email
          assert_receive {:email, %{to: [{_, ^address}]}}
        end

        refute_receive {:email, _}
        baseline = counts()
        day = Date.add(Date.utc_today(), 14) |> Date.to_iso8601()

        b =
          c.conn
          |> login(person)
          |> visit("/#{locale}")
          |> PhoenixTest.Playwright.click("#involvement-menu summary")
          |> capture(id, "Applicant opens Get involved", "Click Local groups")
          |> click_link("#act-local-groups", tr(locale, "Local groups"), exact: true)
          |> assert_has("[data-phx-main].phx-connected")
          |> capture(id, "Configured local group directory", "Click Request to join")
          |> click_link(tr(locale, "Request to join"))
          |> assert_has("[data-phx-main].phx-connected")
          |> check(tr(locale, "I agree to follow these conduct rules."))
          |> click_button(tr(locale, "Save request"))
          |> assert_has("#my-membership", text: tr(locale, "Pending review"), exact: false)
          |> capture(
            id,
            "Applicant saves a pending group request",
            "The manager can now select this applicant for a welcome call without granting an organizer role"
          )

        assert Repo.get!(Accounts.User, person.id).organizing_group_id == nil
        assert {:error, :unauthorized} = PauseAiCa.AccountManagement.get(scope, person.id)

        b =
          switch_browser_identity(b, &login(&1, manager))
          |> visit("/manage/accounts?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")
          |> capture(id, "Accounts workspace", "Click Welcome calls in Management")
          |> click_link(tr(locale, "Welcome calls"))
          |> assert_has("#welcome-list")
          |> click_link(tr(locale, "Add welcome call"))
          |> assert_has("[data-welcome-form]")
          |> fill_in(tr(locale, "Title"), with: "Synthetic welcome")
          |> select("[name='session[language]']", tr(locale, "Session language"),
            exact: false,
            option: tr(locale, if(locale == "fr", do: "French", else: "English"))
          )
          |> fill_in(tr(locale, "Local start time"), with: day <> "T15:00")
          |> fill_in(tr(locale, "Local end time"), with: day <> "T16:00")
          |> fill_in(tr(locale, "HTTPS meeting link"), with: "https://example.org/welcome-call")
          |> click_button(tr(locale, "Save"))
          |> assert_has("#welcome-editor[data-revision='1']")

        {:ok, [session]} = Welcome.list(scope, group.id)
        path = "/manage/welcome-calls/#{session.id}?group=#{group.id}&locale=#{locale}"

        b =
          b
          |> assert_has("#welcome-editor[data-session-id='#{session.id}']")
          |> check("Camille")
          |> click_button(tr(locale, "Add selected people"))
          |> assert_has("#welcome-editor[data-revision='2']")

        p = Repo.one!(Participant)

        b =
          b
          |> assert_has("#welcome-person-#{p.id}", text: "Camille")
          |> capture(
            id,
            "Select Camille for the call",
            "Four independent invitation, RSVP, attendance and follow-up states are visible"
          )
          |> click_button(tr(locale, "Prepare invitation drafts"))
          |> assert_has("#welcome-person-#{p.id} a[href*='/manage/mail/']")
          |> capture(
            id,
            "Prepare invitation drafts",
            "An exact one-account private draft is saved; nothing is sent"
          )

        batch = Repo.one!(PauseAiCa.Mail.Batch)
        assert batch.recipient_ids == [person.id]
        assert Repo.aggregate(PauseAiCa.Mail.Draft, :count) == 1
        assert Repo.get!(Participant, p.id).invitation_state == "selected"

        assert batch.recipient_context == %{
                 "purpose" => "welcome",
                 "group_id" => group.id,
                 "session_id" => session.id
               }

        b =
          b
          |> click_link(tr(locale, "Open invitation drafts (author only)"))
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#mail-recipients", text: person.email)
          |> refute_has("#mail-recipient-search-form")
          |> capture(
            id,
            "Author opens the purpose-bound invitation draft",
            "Recipients stay bound to this welcome call; no account-management grant or send"
          )
          |> click_link("#mail-recipients a", tr(locale, "Welcome calls"), exact: true)
          |> assert_has("#welcome-editor")
          |> click_button(tr(locale, "Record invitation shared"))
          |> assert_has("#welcome-person-#{p.id}", text: tr(locale, "Invitation recorded"))

        b =
          switch_browser_identity(b, &login(&1, person))
          |> visit(if(locale == "fr", do: "/fr/appels-accueil", else: "/en/welcome-calls"))
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#my-welcome-#{p.id}", text: "Synthetic welcome")
          |> refute_has("a[href='https://example.org/welcome-call']")
          |> capture(
            id,
            "Invited account opens My welcome calls",
            "Choose Accept; no profile is entered again"
          )
          |> click_button(tr(locale, "Accept"))
          |> assert_has("#my-welcome-#{p.id}[data-revision='4']")
          |> assert_has("a[href='https://example.org/welcome-call']")
          |> capture(
            id,
            "Accept the invitation",
            "Meeting access is shown; attendance remains unrecorded"
          )

        assert Repo.get!(Participant, p.id).attendance == "unknown"
        assert Repo.get!(Participant, p.id).follow_up == "pending"

        # Simulate time passing in this synthetic fixture. There is no real
        # meeting or claim that a media session took place.
        Repo.get!(Session, session.id)
        |> Ecto.Changeset.change(
          starts_at: DateTime.add(DateTime.utc_now(), -7200),
          ends_at: DateTime.add(DateTime.utc_now(), -3600)
        )
        |> Repo.update!()

        b =
          switch_browser_identity(b, &login(&1, manager))
          |> visit(path)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#welcome-editor[data-session-id='#{session.id}']")
          |> select(
            "#welcome-outcome-#{p.id} [name='person[attendance]']",
            tr(locale, "Attendance"),
            exact: false,
            option: tr(locale, "Attended")
          )
          |> select(
            "#welcome-outcome-#{p.id} [name='person[follow_up]']",
            tr(locale, "Follow-up"),
            exact: false,
            option: tr(locale, "Completed")
          )
          |> fill_in(tr(locale, "Private follow-up notes"), with: "Resources shared")
          |> click_button(tr(locale, "Record outcome"))
          |> assert_has("#welcome-person-#{p.id}", text: tr(locale, "Attended"))
          |> assert_has("#welcome-person-#{p.id}", text: tr(locale, "Completed"))
          |> capture(
            id,
            "Manager records the synthetic ended-call outcome",
            "Attendance and follow-up are explicit actions, independent of RSVP"
          )

        updated = Repo.get!(Participant, p.id)

        assert updated.rsvp == "accepted" and updated.attendance == "attended" and
                 updated.follow_up == "completed"

        assert updated.attendance_by_id == manager.id
        assert counts() == baseline
        refute_receive {:email, _}

        PhoenixTest.Playwright.evaluate(
          b,
          "document.documentElement.scrollWidth <= window.innerWidth",
          &assert(&1)
        )

        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
        b
      end
    end

    defp counts,
      do: %{
        accounts: Repo.aggregate(Accounts.User, :count),
        subscriptions: Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count),
        memberships: Repo.aggregate(Volunteers.Manager, :count),
        deliveries: Repo.aggregate(PauseAiCa.Newsletters.Delivery, :count)
      }

    defp login(b, user) do
      {token, _} = generate_user_magic_link_token(user)

      b
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(b, id, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        b,
        "document.documentElement.scrollWidth <= window.innerWidth",
        &assert(&1)
      )

      step = Process.get({:welcome_step, id}, 0) + 1
      Process.put({:welcome_step, id}, step)
      name = "#{id}-#{step}.png"
      PhoenixTest.Playwright.evaluate(b, "location.href", &Process.put(:welcome_url, &1))

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "url" => AtddEvidence.safe_url(Process.get(:welcome_url)),
        "control" => control,
        "source" =>
          "Actual local proposed UI; synthetic pending incubator applicant; no send/calendar/media",
        "external_systems" => "None"
      }

      AcceptanceHarness.Evidence.record_pending_step(name, control, outcome, metadata)
      b = AtddEvidence.capture_full_page(b, name)

      AtddEvidence.record_step(
        name,
        control,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(b)))
      )

      b
    end
  end
end
