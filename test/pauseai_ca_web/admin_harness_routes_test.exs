defmodule PauseAiCaWeb.AdminHarnessRoutesTest do
  use PauseAiCaWeb.ConnCase

  import PauseAiCa.AccountsFixtures
  import Phoenix.LiveViewTest

  alias PauseAiCa.Repo

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{admin_conn: log_in_user(conn, admin)}
  end

  test "a superadmin can open deployment versions", %{admin_conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/versions")
    assert html =~ "Deployment versions"
  end

  test "a superadmin can open acceptance evidence", %{admin_conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/acceptance")
    assert html =~ "Acceptance"
  end

  test "a regular account cannot access harness admin pages", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    assert conn |> get("/admin/versions") |> response(403) == "superadmin required"

    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user)
    assert conn |> get("/admin/acceptance") |> response(403) == "superadmin required"
  end
end
