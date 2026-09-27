defmodule PauseAiCa.ReportingCalendarTest do
  use PauseAiCa.DataCase, async: true
  alias PauseAiCa.{ReportingCalendar, Engagement}
  alias PauseAiCa.Engagement.DailyVisit
  import PauseAiCa.AccountsFixtures

  test "Canadian dates roll over at Toronto midnight, including daylight saving transitions" do
    assert ReportingCalendar.today(~U[2026-09-27 00:30:00Z]) == ~D[2026-09-26]
    assert ReportingCalendar.today(~U[2026-09-27 03:59:59Z]) == ~D[2026-09-26]
    assert ReportingCalendar.today(~U[2026-09-27 04:00:00Z]) == ~D[2026-09-27]
    assert ReportingCalendar.today(~U[2026-01-02 04:59:59Z]) == ~D[2026-01-01]
    assert ReportingCalendar.today(~U[2026-01-02 05:00:00Z]) == ~D[2026-01-02]

    assert DateTime.diff(
             ReportingCalendar.starts_at(~D[2026-03-09]),
             ReportingCalendar.starts_at(~D[2026-03-08]),
             :hour
           ) == 23

    assert DateTime.diff(
             ReportingCalendar.starts_at(~D[2026-11-02]),
             ReportingCalendar.starts_at(~D[2026-11-01]),
             :hour
           ) == 25
  end

  test "account cohorts and trends include the Canadian evening after UTC midnight" do
    user = user_fixture()
    user |> Ecto.Changeset.change(inserted_at: ~U[2026-09-27 03:59:59Z]) |> Repo.update!()
    assert Engagement.signup_funnel(%{"from" => "2026-09-26", "to" => "2026-09-26"}).created == 1
    assert Engagement.signup_funnel(%{"from" => "2026-09-27", "to" => "2026-09-27"}).created == 0
    assert List.last(Engagement.metrics(~D[2026-09-26]).trends.users) == 1
    user |> Ecto.Changeset.change(inserted_at: ~U[2026-09-27 04:00:00Z]) |> Repo.update!()
    assert Engagement.signup_funnel(%{"from" => "2026-09-26", "to" => "2026-09-26"}).created == 0
  end

  test "legacy UTC visit totals remain distinct from new Canadian-day chart data" do
    Repo.insert!(%DailyVisit{visited_on: ~D[2026-09-26], reporting_timezone: "UTC", count: 542})
    Engagement.record_visit(~D[2026-09-26])
    Engagement.record_visit(~D[2026-09-26])
    metrics = Engagement.metrics(~D[2026-09-26])
    assert metrics.visits == 544
    assert metrics.trends.visits == [2]
    assert Repo.aggregate(DailyVisit, :count) == 2
  end
end
