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

  test "selected accounts open the list chooser and add canonical contacts", %{
    conn: conn,
    admin: admin
  } do
    scope = Scope.for_user(admin)
    target = user_fixture(%{email: "account-list-choice@example.org"})

    {:ok, list} =
      PauseAiCa.ContactLists.save(scope, nil, %{"name" => "Account helpers", "kind" => "static"})

    {:ok, view, _} = live(conn, "/manage/accounts?locale=en&q=account-list-choice")
    view |> element("#account-select-#{target.id}") |> render_click()
    view |> element("#account-list-selected") |> render_click()
    assert has_element?(view, "#account-add-to-list option[value='#{list.id}']", list.name)

    view
    |> form("#account-add-to-list", %{"collection" => %{"list_id" => list.id}})
    |> render_submit()

    assert {:ok, saved} = PauseAiCa.ContactLists.get(scope, list.id)
    assert [person_id] = saved.criteria["person_ids"]
    assert Repo.get_by!(PhoenixCRM.Address, email: target.email).person_id == person_id
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

  test "search bookmarks and Enter retain filtering and show empty results", %{conn: conn} do
    target = unconfirmed_user_fixture(%{email: "search-person@example.org"})
    unrelated = user_fixture(%{email: "unrelated-person@example.org"})

    {:ok, view, _} = live(conn, "/manage/accounts?locale=en&search=search-person")
    assert has_element?(view, "#account-search-input[value='search-person']")
    assert has_element?(view, "#account-count", "1 account")
    assert has_element?(view, "a", target.email)
    refute has_element?(view, "a", unrelated.email)

    view |> form("#account-search", %{search: "missing-account"}) |> render_submit()
    assert_patch(view, "/manage/accounts?locale=en&q=missing-account")
    assert has_element?(view, "#account-search-input[value='missing-account']")
    assert has_element?(view, "#account-count", "0 accounts")
    assert has_element?(view, "p", "No accounts found.")
    refute has_element?(view, "a", target.email)

    view |> form("#account-search", %{search: "search-person"}) |> render_submit()
    assert_patch(view, "/manage/accounts?locale=en&q=search-person")
    assert has_element?(view, "a", target.email)
    assert has_element?(view, "td", "Account created · email unconfirmed")

    {:ok, canonical, _} =
      live(conn, "/manage/accounts?locale=en&q=missing-account&search=search-person")

    assert has_element?(canonical, "#account-count", "0 accounts")
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

  test "staging role grant notifies only the acting admin and preserves unrelated state", %{
    conn: conn,
    admin: admin
  } do
    target = user_fixture()
    flush_emails()
    before_accounts = Repo.aggregate(Accounts.User, :count)
    before_invitations = Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count)
    previous = Application.fetch_env!(:pauseai_ca, :mail_environment)
    Application.put_env(:pauseai_ca, :mail_environment, :staging)
    on_exit(fn -> Application.put_env(:pauseai_ca, :mail_environment, previous) end)

    {:ok, view, _} = live(conn, "/manage/accounts/#{target.id}?locale=en")
    view |> element("#account-superadmin") |> render_click()
    html = view |> element("#role-confirmation button") |> render_click()
    assert html =~ "Superadmin role granted."
    assert_receive {:email, notification}
    assert notification.to == [{"Staging admin", admin.email}]
    assert notification.cc == [] and notification.bcc == [] and notification.reply_to == nil
    assert notification.subject =~ "[STAGING]"
    assert notification.text_body =~ "/manage/accounts"
    refute_receive {:email, _}

    promoted = Accounts.get_user!(target.id)
    assert promoted.superadmin

    assert Map.drop(Map.from_struct(promoted), [:superadmin, :updated_at]) ==
             Map.drop(Map.from_struct(target), [:superadmin, :updated_at])

    assert Accounts.get_user!(admin.id).superadmin
    assert Repo.aggregate(Accounts.User, :count) == before_accounts
    assert Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count) == before_invitations

    {:ok, roster, _} =
      live(log_in_user(build_conn(), promoted), "/manage/administrators?locale=en")

    assert has_element?(roster, "#superadmin-list", target.email)
    render_click(view, "set-superadmin", %{"enabled" => "true"})
    refute_receive {:email, _}
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  test "account collection keeps explicit selection across filters and selects all matches", %{
    conn: conn
  } do
    people = for n <- 1..26, do: user_fixture(%{email: "collection-#{n}@example.org"})
    {:ok, view, _} = live(conn, "/manage/accounts?locale=en&q=collection-")
    assert has_element?(view, "#account-collection-select-page[type=checkbox]")
    view |> element("button[phx-click=select-all-accounts]") |> render_click()
    assert has_element?(view, "#account-collection-selection", "26 selected across pages")
    view |> form("#account-search", %{search: "not-matching"}) |> render_change()

    assert has_element?(
             view,
             "#account-collection-selection",
             "26 selected outside the current filters"
           )

    render_click(view, "select-account", %{"id" => hd(people).id})
    assert has_element?(view, "#account-collection-selection", "26 selected across pages")
    view |> element("button[phx-click=clear-account-selection]") |> render_click()
    assert has_element?(view, "#account-collection-selection", "0 selected across pages")
  end

  test "manager collection never offers global list administration and matching IDs stay fresh-scoped",
       %{conn: conn, admin: admin} do
    scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(scope, %{name: "Collection group"})
    manager = user_fixture()
    {:ok, grant} = Volunteers.assign_manager(scope, group.id, manager.email)

    target =
      user_fixture() |> Ecto.Changeset.change(organizing_group_id: group.id) |> Repo.update!()

    foreign = user_fixture()
    manager_scope = Scope.for_user(manager)
    assert {:ok, ids} = AccountManagement.matching_ids(manager_scope)
    assert ids == [target.id]
    {:ok, view, _} = live(log_in_user(recycle(conn), manager), "/manage/accounts?locale=en")
    refute has_element?(view, "#account-list-selected")
    refute has_element?(view, "#account-select-#{foreign.id}")
    view |> element("button[phx-click=select-all-accounts]") |> render_click()
    assert has_element?(view, "#account-collection-selection", "1 selected across pages")
    :ok = Volunteers.revoke_manager(scope, grant.id)
    assert {:error, :unauthorized} = AccountManagement.matching_ids(manager_scope)
    assert AccountManagement.selected_matching_ids(manager_scope, "", [target.id]) == []
    render_click(view, "collection-email", %{})
    assert has_element?(view, "#account-collection-error")
    assert Repo.aggregate(PauseAiCa.Mail.Batch, :count) == 0
  end
end
