defmodule PauseAiCaWeb.AdminAccountsLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  import Swoosh.TestAssertions
  alias PauseAiCa.{Accounts, AccountManagement, Repo, Volunteers}
  alias PauseAiCa.Accounts.Scope

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{admin: admin, conn: log_in_user(conn, admin)}
  end

  test "old bookmarks redirect with locale and pagination", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/manage/accounts?locale=fr&page=2"}}} =
             live(conn, "/admin/accounts?locale=fr&page=2")
  end

  test "directory counts, stable pagination and bounded pages", %{conn: conn} do
    for n <- 1..26,
        do:
          user_fixture(%{
            email: "account-#{String.pad_leading(to_string(n), 2, "0")}@example.com"
          })

    {:ok, first, _} = live(conn, "/manage/accounts")
    assert has_element?(first, "#account-count", "27 accounts")
    assert has_element?(first, "#account-page", "Page 1 of 2")
    assert has_element?(first, "a", "account-01@example.com")
    refute has_element?(first, "a", "account-26@example.com")
    {:ok, last, _} = live(conn, "/manage/accounts?page=999")
    assert has_element?(last, "#account-page", "Page 2 of 2")
    assert has_element?(last, "a", "account-26@example.com")
    {:ok, invalid, _} = live(conn, "/manage/accounts?page=invalid")
    assert has_element?(invalid, "#account-page", "Page 1 of 2")
  end

  test "confirmed role grant sends once, and unconfirmed and last-admin guards remain", %{
    conn: conn,
    admin: admin
  } do
    target = user_fixture()
    flush_emails()
    {:ok, view, _} = live(conn, "/manage/accounts/#{target.id}")
    view |> element("#account-superadmin") |> render_click()
    view |> element("#role-confirmation button") |> render_click()
    assert Accounts.get_user!(target.id).superadmin

    assert_email_sent(fn email ->
      assert email.to == [{"", target.email}]
      assert email.text_body =~ "/manage/accounts"
    end)

    assert {:ok, {_, false}} =
             AccountManagement.set_superadmin(Scope.for_user(admin), target.id, true)

    unconfirmed = unconfirmed_user_fixture()
    {:ok, view, _} = live(conn, "/manage/accounts/#{unconfirmed.id}")
    assert has_element?(view, "#account-superadmin[disabled]")

    assert {:error, :email_unconfirmed} =
             AccountManagement.set_superadmin(Scope.for_user(admin), unconfirmed.id, true)

    assert {:ok, _} = AccountManagement.set_superadmin(Scope.for_user(admin), target.id, false)

    assert {:error, :last_superadmin} =
             AccountManagement.set_superadmin(Scope.for_user(admin), admin.id, false)
  end

  test "manager cannot forge a role change and a revoked admin cannot reuse an old scope", %{
    admin: admin
  } do
    scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(scope, %{"name" => "Montréal"})
    manager = user_fixture()
    {:ok, _} = Volunteers.assign_manager(scope, group.id, manager.email)

    target =
      user_fixture() |> Ecto.Changeset.change(organizing_group_id: group.id) |> Repo.update!()

    {:ok, view, _} = live(log_in_user(build_conn(), manager), "/manage/accounts/#{target.id}")
    refute has_element?(view, "#account-access")
    render_click(view, "set-superadmin", %{"enabled" => "true"})
    refute Accounts.get_user!(target.id).superadmin
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = AccountManagement.set_superadmin(scope, target.id, true)
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
