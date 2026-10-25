defmodule PauseAiCaWeb.WelcomeCallsLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Welcome, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Welcome.Participant

  setup %{conn: conn} do
    previous = Application.get_env(:pauseai_ca, :welcome_calls_enabled)
    Application.put_env(:pauseai_ca, :welcome_calls_enabled, true)
    on_exit(fn -> Application.put_env(:pauseai_ca, :welcome_calls_enabled, previous) end)
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    manager = user_fixture() |> Ecto.Changeset.change(name: "Alex") |> Repo.update!()
    scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(scope, %{name: "Welcome UI group"})
    {:ok, grant} = Volunteers.assign_manager(scope, group.id, manager.email)

    newcomer =
      user_fixture()
      |> Ecto.Changeset.change(name: "Blair", organizing_group_id: group.id)
      |> Repo.update!()

    %{
      conn: log_in_user(conn, manager),
      manager: manager,
      scope: Scope.for_user(manager),
      admin: scope,
      group: group,
      grant: grant,
      newcomer: newcomer
    }
  end

  test "manager schedules a local-time session and prepares only the selected account's private draft",
       c do
    {:ok, view, _} = live(c.conn, "/manage/welcome-calls/new?group=#{c.group.id}&locale=en")

    day = Date.add(Date.utc_today(), 14) |> Date.to_iso8601()

    view
    |> form("[data-welcome-form]",
      session: %{
        title: "First welcome call",
        host_id: c.manager.id,
        language: "en",
        timezone: "America/Toronto",
        local_start: day <> "T15:00",
        local_end: day <> "T16:00",
        meeting_url: "https://example.org/call"
      }
    )
    |> render_submit()

    {:ok, [session]} = Welcome.list(c.scope, c.group.id)
    {:ok, expected_start} = Welcome.local_time(day <> "T15:00", "America/Toronto")
    assert DateTime.compare(session.starts_at, expected_start) == :eq
    assert has_element?(view, "#welcome-editor[data-session-id='#{session.id}']")
    view |> form("#welcome-select", people: [c.newcomer.id]) |> render_submit()
    assert has_element?(view, "#welcome-cohort", "Blair")
    view |> element("button", "Prepare invitation drafts") |> render_click()
    assert has_element?(view, "a", "Open invitation drafts")
    p = Repo.one!(Participant)
    assert p.user_id == c.newcomer.id and p.invitation_state == "selected"
    assert p.rsvp == "pending" and p.attendance == "unknown"
    assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
    assert Repo.aggregate(PauseAiCa.Newsletters.Delivery, :count) == 0
  end

  test "only the selected confirmed account can RSVP; private notes are never rendered to applicants",
       c do
    {:ok, session} =
      Welcome.create(
        c.scope,
        c.group.id,
        %{
          "title" => "Private welcome",
          "host_id" => c.manager.id,
          "language" => "fr",
          "timezone" => "America/Toronto",
          "starts_at" => DateTime.add(DateTime.utc_now(), 3600),
          "ends_at" => DateTime.add(DateTime.utc_now(), 7200),
          "meeting_url" => "https://example.org/private-call"
        },
        "create"
      )

    {:ok, _} =
      Welcome.select(c.scope, c.group.id, session.id, [c.newcomer.id], session.revision, "select")

    p = Repo.one!(Participant)
    {:ok, p} = Welcome.record_invited(c.scope, c.group.id, session.id, p.id, p.revision, "invite")
    p |> Ecto.Changeset.change(notes: "Private manager note") |> Repo.update!()
    {:ok, own, html} = live(log_in_user(build_conn(), c.newcomer), "/fr/appels-accueil")
    refute html =~ "Private manager note"
    assert has_element?(own, "#my-welcome-#{p.id}", "Private welcome")
    refute has_element?(own, "a[href='https://example.org/private-call']")
    own |> element("button[phx-value-reply=accepted]") |> render_click()
    assert has_element?(own, "a[href='https://example.org/private-call']")
    assert Repo.get!(Participant, p.id).attendance == "unknown"
    outsider = user_fixture()
    {:ok, foreign, _} = live(log_in_user(build_conn(), outsider), "/en/welcome-calls")
    refute render(foreign) =~ "Private welcome"
    assert Repo.aggregate(PauseAiCa.Volunteers.Manager, :count) == 1
  end

  test "revoked management authority removes an already-open session", c do
    {:ok, view, _} = live(c.conn, "/manage/welcome-calls?group=#{c.group.id}&locale=en")
    :ok = Volunteers.revoke_manager(c.admin, c.grant.id)
    send(view.pid, :refresh_access)
    assert_redirect(view, "/dashboard")
  end
end
