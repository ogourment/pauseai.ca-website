defmodule PauseAiCaWeb.NavigationTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Volunteers.Manager
  alias PauseAiCaWeb.Navigation

  test "superadmin gets separate Admin, Management and own account navigation", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    {:ok, view, _} = live(log_in_user(conn, admin), "/admin/contacts?locale=en")
    assert has_element?(view, "#management-tabs [data-area=admin]", "Contacts")
    assert has_element?(view, "#management-tabs [data-area=manage]", "Emails")
    assert has_element?(view, "[data-navigation-item=\"pauseai.contacts\"][aria-current=page]")
    assert has_element?(view, "#account-management-links [data-area=account]", "My profile")
    refute has_element?(view, "#management-tabs [data-area=account]")
  end

  test "group manager retains scoped routes and never receives global contact/admin links", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    manager = user_fixture()

    {:ok, group} =
      Volunteers.create_group(Scope.for_user(admin), %{"name" => "Navigation Montréal"})

    {:ok, grant} = Volunteers.assign_manager(Scope.for_user(admin), group.id, manager.email)
    {:ok, view, _} = live(log_in_user(conn, manager), "/manage/accounts?locale=en")
    assert has_element?(view, "#management-tabs [data-area=manage]", "Accounts")
    refute has_element?(view, "#management-tabs [data-area=admin]")

    assert get(log_in_user(conn, manager), "/admin/contacts?locale=en").status == 403

    Repo.delete!(Repo.get!(Manager, grant.id))
    items = Navigation.assemble(Scope.for_user(manager), "en")
    assert Enum.all?(items, &(&1.area == :account))

    assert {:error, {:redirect, _}} =
             live(log_in_user(conn, manager), "/manage/accounts?locale=en")
  end

  test "fresh revoked superadmin authority overrides stale session flags" do
    user = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    stale = Scope.for_user(user)
    user |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert Enum.all?(Navigation.assemble(stale, "en"), &(&1.area == :account))
  end

  test "ordinary account navigation exposes only self and assembly has no business writes" do
    user = user_fixture()
    before = counts()

    assert Enum.map(Navigation.assemble(Scope.for_user(user), "en"), & &1.id) == [
             "pauseai.my-dashboard",
             "pauseai.my-profile",
             "pauseai.settings",
             "pauseai.password"
           ]

    assert Navigation.assemble(nil, "en") == []
    assert counts() == before
  end

  defp counts,
    do:
      Enum.map(
        [
          PauseAiCa.Accounts.User,
          PauseAiCa.ContactMigration.Contact,
          PauseAiCa.Volunteers.Manager,
          PauseAiCa.Volunteers.Invitation,
          PauseAiCa.Mail.Batch,
          PauseAiCa.Mail.Draft
        ],
        &Repo.aggregate(&1, :count)
      )
end
