defmodule PauseAiCa.AccountManagementTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{AccountManagement, Volunteers}
  alias PauseAiCa.Accounts.{Scope, User}
  alias PauseAiCa.Volunteers.{Input, Manager, Signup}

  test "directory and writes share group scope; revocation and submitted privileges cannot bypass it" do
    admin =
      user_fixture()
      |> change(superadmin: true, confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(scope, %{"name" => "Montréal"})
    manager = user_fixture() |> change(confirmed_at: DateTime.utc_now(:second)) |> Repo.update!()
    {:ok, role} = Volunteers.assign_manager(scope, group.id, manager.email)
    row = Input.normalize(%{"email" => "managed@example.org", "selected" => true})

    {:ok, batch} =
      Volunteers.save_draft(scope, nil, %{"default_group_id" => group.id, "rows" => [row]})

    {:ok, _} = Volunteers.confirm(scope, batch.id)
    account = Repo.one!(from u in User, where: u.email == "managed@example.org")
    manager_scope = Scope.for_user(manager)
    assert [%{user: %{id: id}}] = AccountManagement.list(manager_scope)
    assert id == account.id
    assert {:error, :unauthorized} = AccountManagement.get(manager_scope, admin.id)

    assert {:error, :unauthorized} =
             AccountManagement.update(manager_scope, admin.id, %{"name" => "No"})

    assert {:ok, updated} =
             AccountManagement.update(manager_scope, account.id, %{
               "name" => "Corrected",
               "postal_code" => "H2X1Y4",
               "superadmin" => true,
               "local_updates" => true,
               "email" => "other@example.org",
               "notes" => "Private"
             })

    assert updated.name == "Corrected"
    assert updated.fsa == "H2X"
    refute updated.superadmin
    refute updated.local_updates
    assert updated.email == "managed@example.org"
    assert Repo.one!(Signup).notes == "Private"
    Repo.delete!(Repo.get!(Manager, role.id))
    assert [] = AccountManagement.list(manager_scope)

    assert {:error, :unauthorized} =
             AccountManagement.update(manager_scope, account.id, %{"name" => "Forbidden"})

    assert Repo.get!(User, account.id).name == "Corrected"
    assert Enum.any?(AccountManagement.list(scope), &(&1.user.id == admin.id))
  end
end
