defmodule PauseAiCaWeb.AdminAccountsLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  import Swoosh.TestAssertions

  alias PauseAiCa.{Accounts, Repo}

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{admin: admin, conn: log_in_user(conn, admin)}
  end

  test "lists accounts separately from movement metrics", %{conn: conn, admin: admin} do
    target = user_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/accounts")

    assert has_element?(view, "#admin-accounts")
    assert has_element?(view, "#account-count", "2 accounts")
    assert has_element?(view, "#admin-user-#{admin.id}", admin.email)
    assert has_element?(view, "#admin-user-#{target.id}", target.email)
    assert has_element?(view, "a[aria-current='page'][href='/admin/accounts']", "Accounts")
    assert has_element?(view, "a[href='/admin/dashboard']", "Dashboard")
    refute has_element?(view, "#admin-metrics")
  end

  test "paginates accounts in stable email order", %{conn: conn} do
    for number <- 1..26 do
      user_fixture(%{
        email: "account-#{String.pad_leading(Integer.to_string(number), 2, "0")}@example.com"
      })
    end

    {:ok, first_page, _html} = live(conn, ~p"/admin/accounts")

    assert has_element?(first_page, "#account-page", "Page 1 of 2")
    assert has_element?(first_page, "a[href='/admin/accounts?page=2']", "Next")
    assert has_element?(first_page, "[id^='admin-user-']", "account-01@example.com")
    refute has_element?(first_page, "[id^='admin-user-']", "account-26@example.com")

    {:ok, second_page, _html} = live(conn, ~p"/admin/accounts?page=2")

    assert has_element?(second_page, "#account-page", "Page 2 of 2")
    assert has_element?(second_page, "a[href='/admin/accounts?page=1']", "Previous")
    assert has_element?(second_page, "[id^='admin-user-']", "account-26@example.com")
  end

  test "an invalid or out-of-range page resolves to a valid account page", %{conn: conn} do
    {:ok, invalid_page, _html} = live(conn, ~p"/admin/accounts?page=invalid")
    assert has_element?(invalid_page, "[id^='admin-user-']")

    {:ok, high_page, _html} = live(conn, ~p"/admin/accounts?page=999")
    assert has_element?(high_page, "[id^='admin-user-']")
  end

  test "an unconfirmed account cannot be promoted", %{conn: conn, admin: admin} do
    target = unconfirmed_user_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/accounts")

    assert has_element?(view, "#admin-toggle-#{target.id}[disabled]")
    assert {:error, :email_unconfirmed} = Accounts.set_superadmin(admin, target, true)
  end

  test "a superadmin can promote a confirmed account from the accounts page", %{conn: conn} do
    target = user_fixture()
    flush_emails()
    {:ok, view, _html} = live(conn, ~p"/admin/accounts")

    assert has_element?(view, "#admin-toggle-#{target.id}[data-confirm*='will receive an email']")

    view
    |> element("#admin-toggle-#{target.id}")
    |> render_click()

    assert Accounts.get_user!(target.id).superadmin
    assert has_element?(view, "#admin-user-#{target.id}", "Superadmin")
    assert render(view) =~ "Superadmin role granted."

    assert_email_sent(fn email ->
      assert email.to == [{"", target.email}]
      assert email.subject =~ "You are now a PauseAI Canada superadmin"
      assert email.text_body =~ "/admin/accounts"
    end)
  end

  test "promotion is derived from the current role, not a browser toggle value", %{conn: conn} do
    target = user_fixture()
    flush_emails()
    {:ok, view, _html} = live(conn, ~p"/admin/accounts")

    render_click(view, "set-superadmin", %{"id" => target.id, "value" => ""})

    assert Accounts.get_user!(target.id).superadmin
    assert render(view) =~ "Superadmin role granted."
  end

  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
