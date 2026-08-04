defmodule PauseAiCaWeb.AdminMetricsLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures

  alias PauseAiCa.{Accounts, Repo}

  test "a confirmed superadmin sees first-party database metrics", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/admin/metrics")

    assert has_element?(view, "#admin-metrics")
    assert has_element?(view, "#metric-users")
    assert has_element?(view, "#metrics-by-type")
    assert has_element?(view, "a[href='/admin/versions']", "Deployment versions")
    assert has_element?(view, "a[href='/admin/acceptance']", "Acceptance evidence")
  end

  test "a regular account is redirected", %{conn: conn} do
    user = user_fixture()

    assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
             live(log_in_user(conn, user), ~p"/admin/metrics")
  end

  test "an unconfirmed account cannot be promoted", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    target = unconfirmed_user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/admin/metrics")

    assert has_element?(view, "#admin-toggle-#{target.id}[disabled]")
    assert {:error, :email_unconfirmed} = Accounts.set_superadmin(admin, target, true)
  end
end
