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
    assert has_element?(view, "#metric-visits.overflow-hidden")
    assert has_element?(view, "#metric-visits", "Browser visits — all time")
    assert has_element?(view, "#visit-measurement-note", "not unique people")
    assert has_element?(view, "#metric-montreal-protest-interest", "1")
    assert has_element?(view, "#metric-montreal-protest-interest", "September 26 event link")
    assert has_element?(view, "#movement-participation-metrics")
    assert has_element?(view, "#organizer-task-metrics #metric-organizer-tasks-active", "Active")

    assert has_element?(
             view,
             "#incubator-metrics #metric-incubator-memberships",
             "Approved memberships"
           )

    assert has_element?(view, "#newsletter-metrics #metric-newsletter-opens", "Reported opens")
    assert has_element?(view, "#newsletter-metrics-coverage", "0 of 0")
    refute has_element?(view, "#metric-newsletter-opens svg")
    assert has_element?(view, "#incubator-metrics #metric-incubators", "Published")

    assert has_element?(
             view,
             "#organizer-task-metrics #metric-organizer-tasks-completed",
             "Completed"
           )

    assert has_element?(view, "#movement-metrics-units", "neither proves reading")
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
    assert has_element?(view, "#management-tabs a[aria-current='page']", "Dashboard")
    assert has_element?(view, "#management-tabs a[href='/manage/accounts?locale=en']", "Accounts")
    assert has_element?(view, "a[href='/admin/versions']", "Deployment versions")
    assert has_element?(view, "a[href='/admin/acceptance']", "Acceptance evidence")
  end

  test "Interac card separates pending declarations from bank-verified money in both editions", %{
    conn: conn
  } do
    alias PauseAiCa.Donations.Interac
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)

    attrs = %{
      "name" => "Synthetic transfer",
      "email" => "metrics-transfer@example.org",
      "amount" => "100.00"
    }

    {:ok, _pending} = Interac.submit(nil, attrs, Ecto.UUID.generate())
    {:ok, received} = Interac.submit(nil, attrs, Ecto.UUID.generate())

    {:ok, _} =
      Interac.verify(
        scope,
        received.id,
        %{"received_amount" => "25.50", "received_on" => "2026-11-01"},
        received.revision
      )

    assert {:ok, %{pending: 1, verified: 1, received_minor: 2550}} = Interac.summary(scope)

    for {locale, title, amount} <- [
          {"en", "Interac donations", "C$25.50"},
          {"fr", "Dons par Interac", "25,50 $ CA"}
        ] do
      {:ok, view, _} = live(log_in_user(conn, admin), "/admin/dashboard?locale=#{locale}")
      assert has_element?(view, "#interac-donation-metrics h3", title)
      assert has_element?(view, "#metric-interac-pending dd", "1")
      assert has_element?(view, "#metric-interac-verified dd", "1")
      assert has_element?(view, "#metric-interac-received dd", amount)
      refute has_element?(view, "#interac-donation-metrics", "100")
      refute has_element?(view, "#interac-donation-metrics", attrs["email"])
    end
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
