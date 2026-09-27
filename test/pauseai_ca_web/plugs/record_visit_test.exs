defmodule PauseAiCaWeb.VisitRecordingTest do
  use PauseAiCaWeb.ConnCase

  alias PauseAiCa.Engagement.DailyVisit
  alias PauseAiCa.Repo

  test "a browser signal counts once per browser and Toronto day", %{conn: conn} do
    conn = conn |> put_private(:record_visits, true) |> post(~p"/engagement/visits")

    assert Repo.get_by!(DailyVisit,
             visited_on: PauseAiCa.ReportingCalendar.today(),
             reporting_timezone: "America/Toronto"
           ).count == 1

    conn |> recycle() |> put_private(:record_visits, true) |> post(~p"/engagement/visits")

    assert Repo.get_by!(DailyVisit,
             visited_on: PauseAiCa.ReportingCalendar.today(),
             reporting_timezone: "America/Toronto"
           ).count == 1
  end

  test "raw page requests do not count as browser visits", %{conn: conn} do
    conn |> put_private(:record_visits, true) |> get(~p"/en")

    refute Repo.get_by(DailyVisit,
             visited_on: PauseAiCa.ReportingCalendar.today(),
             reporting_timezone: "America/Toronto"
           )
  end

  test "a new browser and a new Toronto day contribute separate daily counts", %{conn: conn} do
    yesterday = PauseAiCa.ReportingCalendar.today() |> Date.add(-1) |> Date.to_iso8601()

    conn
    |> Phoenix.ConnTest.init_test_session(%{browser_visit_recorded_on_toronto: yesterday})
    |> put_private(:record_visits, true)
    |> post(~p"/engagement/visits")

    build_conn() |> put_private(:record_visits, true) |> post(~p"/engagement/visits")

    assert Repo.get_by!(DailyVisit,
             visited_on: PauseAiCa.ReportingCalendar.today(),
             reporting_timezone: "America/Toronto"
           ).count == 2
  end

  test "superadmin browser signals are excluded", %{conn: conn} do
    admin = PauseAiCa.AccountsFixtures.user_fixture()
    admin = admin |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

    conn
    |> log_in_user(admin)
    |> put_private(:record_visits, true)
    |> post(~p"/engagement/visits")

    refute Repo.get_by(DailyVisit,
             visited_on: PauseAiCa.ReportingCalendar.today(),
             reporting_timezone: "America/Toronto"
           )
  end

  test "recording can be disabled", %{conn: conn} do
    post(conn, ~p"/engagement/visits")

    refute Repo.get_by(DailyVisit,
             visited_on: PauseAiCa.ReportingCalendar.today(),
             reporting_timezone: "America/Toronto"
           )
  end

  test "a signal without CSRF protection cannot increment the count", %{conn: conn} do
    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_private(:record_visits, true)
      |> post(~p"/engagement/visits")
    end

    refute Repo.get_by(DailyVisit,
             visited_on: PauseAiCa.ReportingCalendar.today(),
             reporting_timezone: "America/Toronto"
           )
  end

  test "an old raw-GET marker does not suppress a new browser signal", %{conn: conn} do
    conn
    |> Phoenix.ConnTest.init_test_session(%{
      visit_recorded_on: Date.to_iso8601(PauseAiCa.ReportingCalendar.today())
    })
    |> put_private(:record_visits, true)
    |> post(~p"/engagement/visits")

    assert Repo.get_by!(DailyVisit,
             visited_on: PauseAiCa.ReportingCalendar.today(),
             reporting_timezone: "America/Toronto"
           ).count == 1
  end

  test "signing in preserves today's anonymous visit marker", %{conn: conn} do
    user = PauseAiCa.AccountsFixtures.user_fixture()
    {token, _} = PauseAiCa.AccountsFixtures.generate_user_magic_link_token(user)

    conn = conn |> put_private(:record_visits, true) |> post(~p"/engagement/visits")
    conn = conn |> recycle() |> get(~p"/users/log-in/#{token}")
    conn = conn |> recycle() |> post(~p"/users/log-in", %{user: %{token: token}})

    conn |> recycle() |> put_private(:record_visits, true) |> post(~p"/engagement/visits")

    assert Repo.get_by!(DailyVisit,
             visited_on: PauseAiCa.ReportingCalendar.today(),
             reporting_timezone: "America/Toronto"
           ).count == 1
  end
end
