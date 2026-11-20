defmodule PauseAiCa.VolunteerAssignmentVisibilityTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Incubators, Repo, Tasks, Volunteers}
  alias PauseAiCa.Accounts.Scope

  test "independent work, multiple cities, retirement and the manager-only assignment edge" do
    admin =
      user_fixture()
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()
      |> Scope.for_user()

    one = user_fixture()
    member = Scope.for_user(one)
    manager = user_fixture()
    manager_scope = Scope.for_user(manager)
    {:ok, a} = Volunteers.create_group(admin, %{name: "Ottawa"})
    {:ok, b} = Volunteers.create_group(admin, %{name: "Gatineau"})
    {:ok, _} = Volunteers.assign_manager(admin, a.id, manager.email)

    for g <- [a, b] do
      Repo.insert!(%Incubators.Membership{
        group_id: g.id,
        user_id: one.id,
        display_name: "Synthetic editor",
        status: "approved"
      })
    end

    ma = Repo.get_by!(Incubators.Membership, group_id: a.id, user_id: one.id)

    for title <- ["Video Editor", "Facilitator"] do
      {:ok, _} =
        Incubators.add_responsibility(manager_scope, a.id, ma.id, ma.revision, %{
          title: title,
          starts_on: Date.utc_today()
        })
    end

    assert %{tasks: [], roles: [_, _]} = Volunteers.my_group_work(member)

    for {g, title} <- [{a, "Edit march footage"}, {a, "Caption the interview"}, {b, "Book room"}] do
      {:ok, _} = Tasks.create(admin, g.id, %{title: title, assignee_id: one.id}, title)
    end

    assert %{tasks: [_, _, _], roles: [_, _]} = Volunteers.my_group_work(member)
    assert {:error, :unauthorized} = Tasks.list(manager_scope, b.id)
    {:ok, [role | _]} = Incubators.responsibilities(manager_scope, a.id)

    {:ok, _} =
      Incubators.end_responsibility(
        manager_scope,
        a.id,
        role.id,
        role.revision,
        Date.add(Date.utc_today(), 7)
      )

    assert %{tasks: [_, _, _], roles: [_, _]} = Volunteers.my_group_work(member)

    {:ok, _} =
      Tasks.create(
        manager_scope,
        a.id,
        %{title: "Manager assignment", assignee_id: manager.id},
        "manager-task"
      )

    assert %{tasks: [%{title: "Manager assignment"}]} = Volunteers.my_group_work(manager_scope)
    grant = Repo.get_by!(Volunteers.Manager, user_id: manager.id)
    assert :ok = Volunteers.revoke_manager(admin, grant.id)
    assert %{tasks: []} = Volunteers.my_group_work(manager_scope)
  end
end
