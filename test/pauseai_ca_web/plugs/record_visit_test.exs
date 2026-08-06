defmodule PauseAiCaWeb.Plugs.RecordVisitTest do
  use PauseAiCaWeb.ConnCase

  alias PauseAiCa.Engagement.DailyVisit
  alias PauseAiCa.Repo

  test "public page requests count once per browser and UTC day", %{conn: conn} do
    conn = conn |> Plug.Conn.put_private(:record_visits, true) |> get(~p"/en")
    assert Repo.get!(DailyVisit, Date.utc_today()).count == 1

    conn |> recycle() |> Plug.Conn.put_private(:record_visits, true) |> get(~p"/en/learn")
    assert Repo.get!(DailyVisit, Date.utc_today()).count == 1
  end

  test "admin requests are not public visits", %{conn: conn} do
    admin = PauseAiCa.AccountsFixtures.user_fixture()
    admin = admin |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

    conn |> log_in_user(admin) |> get(~p"/admin/metrics")
    refute Repo.get(DailyVisit, Date.utc_today())
  end
end
