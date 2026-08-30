defmodule PauseAiCaWeb.AdminMetricsLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Repo
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.EngagementFixtures

  test "a confirmed superadmin sees first-party database metrics", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

    EngagementFixtures.action_fixture(Scope.for_user(admin), %{
      confirmed_at: DateTime.utc_now(:second)
    })

    PauseAiCa.Engagement.record_learning_signal(
      Ecto.UUID.generate(),
      nil,
      "event_link_opened",
      "montreal-protest-2026-09-26"
    )

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/admin/dashboard")

    assert has_element?(view, "#admin-dashboard")
    assert has_element?(view, "#admin-metrics")
    assert has_element?(view, "#metrics-period", "Daily trends")
    assert has_element?(view, "#metric-users svg[role='img']")
    assert has_element?(view, "#metric-users [data-role='daily-max']")
    assert has_element?(view, "#metric-active svg[role='img']")
    assert has_element?(view, "#metric-actions svg[role='img']")
    refute has_element?(view, "#metric-visits svg[role='img']")
    assert has_element?(view, "#metric-montreal-protest-interest", "1")
    assert has_element?(view, "#metric-montreal-protest-interest", "Sept. 26 RSVP")
    assert has_element?(view, "#metrics-by-type")
    refute has_element?(view, "#metrics-by-type [data-role='ladder-trend'][data-label='Learn']")
    assert has_element?(view, "#learning-breakdown")
    assert has_element?(view, "#learning-breakdown summary")
    assert has_element?(view, "#learning-breakdown", "Visited Learn")

    refute has_element?(
             view,
             "#metrics-by-type [data-role='ladder-trend'][data-label='Organize']"
           )

    assert has_element?(view, "#metrics-by-type li", "Learn")
    assert has_element?(view, "#metrics-by-type li", "Organize")
    assert has_element?(view, "a[aria-current='page'][href='/admin/dashboard']", "Dashboard")
    assert has_element?(view, "a[href='/admin/accounts']", "Accounts")
    assert has_element?(view, "a[href='/admin/versions']", "Deployment versions")
    assert has_element?(view, "a[href='/admin/acceptance']", "Acceptance evidence")
  end

  test "the admin root and former metrics path redirect to the dashboard", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    conn = log_in_user(conn, admin)

    assert {:error, {:live_redirect, %{to: "/admin/dashboard"}}} = live(conn, ~p"/admin")

    assert {:error, {:live_redirect, %{to: "/admin/dashboard"}}} =
             live(conn, ~p"/admin/metrics")
  end

  test "a regular account is forbidden by the superadmin route", %{conn: conn} do
    user = user_fixture()

    assert conn |> log_in_user(user) |> get(~p"/admin/dashboard") |> response(403) ==
             "superadmin required"
  end
end
