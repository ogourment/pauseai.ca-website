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

  test "group corrections support non-import accounts, preserve source, and revoke old batch access" do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)
    {:ok, first} = Volunteers.create_group(scope, %{"name" => "Montréal"})
    {:ok, second} = Volunteers.create_group(scope, %{"name" => "Québec"})
    manager = user_fixture()
    {:ok, role} = Volunteers.assign_manager(scope, first.id, manager.email)
    manager_scope = Scope.for_user(manager)
    plain = user_fixture()

    assert {:ok, assigned} =
             AccountManagement.update(scope, plain.id, %{
               "group_id" => first.id,
               "notes" => "Context"
             })

    assert assigned.organizer_notes == "Context"
    assert Repo.aggregate(Signup, :count) == 0

    assert {:error, %{"group_id" => :unauthorized_group}} =
             AccountManagement.update(manager_scope, plain.id, %{"group_id" => second.id})

    assert {:error, %{"group_id" => :unauthorized_group}} =
             AccountManagement.update(manager_scope, plain.id, %{"group_id" => ""})

    {:ok, _} = Volunteers.assign_manager(scope, second.id, manager.email)

    assert {:ok, moved} =
             AccountManagement.update(manager_scope, plain.id, %{"group_id" => second.id})

    assert moved.organizing_group_id == second.id
    row = Input.normalize(%{"email" => "transfer@example.org", "selected" => true})

    {:ok, batch} =
      Volunteers.save_draft(manager_scope, nil, %{"default_group_id" => first.id, "rows" => [row]})

    {:ok, _} = Volunteers.confirm(manager_scope, batch.id)
    signup = Repo.one!(Signup)
    assert {:ok, _} = AccountManagement.update(scope, signup.user_id, %{"group_id" => ""})
    assert {:error, :unauthorized} = AccountManagement.get(manager_scope, signup.user_id)
    assert {:error, :unauthorized} = Volunteers.get_batch(manager_scope, batch.id)
    assert Repo.get!(Signup, signup.id).batch_id == batch.id
    assert Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count) == 1
    Volunteers.revoke_manager(scope, role.id)

    assert {:error, %{"group_id" => :unauthorized_group}} =
             AccountManagement.update(manager_scope, plain.id, %{"group_id" => first.id})

    assert Enum.any?(
             Repo.all(PauseAiCa.Volunteers.Event),
             &(&1.details["old_group_id"] == first.id and &1.details["new_group_id"] == second.id)
           )
  end
end
