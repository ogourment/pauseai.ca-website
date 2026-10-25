defmodule PauseAiCa.TasksTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.{Tasks, Volunteers}
  alias PauseAiCa.Tasks.{Dependency, Event, Task}

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    admin_scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(admin_scope, %{name: "Tasks group"})
    {:ok, foreign_group} = Volunteers.create_group(admin_scope, %{name: "Foreign tasks"})
    users = for _ <- 1..3, do: user_fixture()

    grants =
      for user <- users do
        {:ok, grant} = Volunteers.assign_manager(admin_scope, group.id, user.email)
        grant
      end

    [alex, blair, casey] = users

    %{
      admin: admin_scope,
      group: group,
      foreign: foreign_group,
      alex: alex,
      blair: blair,
      casey: casey,
      grants: grants,
      scope: Scope.for_user(alex)
    }
  end

  test "manual task lifecycle, dependency blocking and canonical replay", c do
    {:ok, prerequisite} =
      Tasks.create(c.scope, c.group.id, %{title: "Choose date"}, "prerequisite")

    attrs = %{
      title: "Confirm room",
      accountable_id: c.alex.id,
      assignee_id: c.blair.id,
      backup_id: c.casey.id,
      due_date: "2026-11-15",
      prerequisite_ids: [prerequisite.id]
    }

    assert {:ok, task} = Tasks.create(c.scope, c.group.id, attrs, "create")
    assert task.requester_id == c.alex.id
    assert task.due_date == ~D[2026-11-15]
    assert {:ok, replay} = Tasks.create(c.scope, c.group.id, attrs, "create")
    assert replay.id == task.id
    assert Repo.aggregate(Task, :count) == 2
    assert Repo.aggregate(Event, :count) == 2

    assert {:error, :command_conflict} =
             Tasks.create(c.scope, c.group.id, %{title: "Changed"}, "create")

    assert {:ok, started} =
             Tasks.update(
               c.scope,
               c.group.id,
               task.id,
               %{status: "in_progress"},
               task.revision,
               "start"
             )

    assert {:error, {:blocked, [%{id: id}]}} =
             Tasks.update(
               c.scope,
               c.group.id,
               task.id,
               %{status: "done"},
               started.revision,
               "finish"
             )

    assert id == prerequisite.id

    {:ok, _} =
      Tasks.update(
        c.scope,
        c.group.id,
        prerequisite.id,
        %{status: "done"},
        prerequisite.revision,
        "prerequisite-done"
      )

    {:ok, completed} =
      Tasks.update(c.scope, c.group.id, task.id, %{status: "done"}, started.revision, "finish")

    assert completed.status == "done"
    assert completed.revision == started.revision + 1

    {:ok, repeated} =
      Tasks.update(c.scope, c.group.id, task.id, %{status: "done"}, started.revision, "finish")

    assert repeated.revision == completed.revision
    assert {:ok, history} = Tasks.activity(c.scope, c.group.id, task.id)
    assert Enum.count(history, &(&1.action == "transitioned")) == 2
    assert {:ok, all_activity} = Tasks.activity(c.scope, c.group.id)

    assert MapSet.new(Enum.map(history, & &1.id))
           |> MapSet.subset?(MapSet.new(Enum.map(all_activity, & &1.id)))
  end

  test "delegation is reasoned, revision guarded and immutable across stale attempts", c do
    {:ok, task} =
      Tasks.create(c.scope, c.group.id, %{title: "Room", assignee_id: c.blair.id}, "create")

    assert {:error, {:validation, _}} =
             Tasks.update(
               c.scope,
               c.group.id,
               task.id,
               %{assignee_id: c.casey.id},
               task.revision,
               "no-reason"
             )

    {:ok, updated} =
      Tasks.update(
        c.scope,
        c.group.id,
        task.id,
        %{assignee_id: c.casey.id, reason: "Blair unavailable"},
        task.revision,
        "delegate"
      )

    assert {:error, :conflict} =
             Tasks.update(
               c.scope,
               c.group.id,
               task.id,
               %{description: "Stale"},
               task.revision,
               "stale"
             )

    assert {:ok, persisted} = Tasks.get(c.scope, c.group.id, task.id)
    assert persisted.assignee_id == c.casey.id
    assert persisted.description == updated.description
    {:ok, events} = Tasks.activity(c.scope, c.group.id, task.id)
    assert Enum.count(events, &(&1.action == "delegated")) == 1
  end

  test "cancellation reopening and replay preserve identity provenance and attributed history",
       c do
    {:ok, task} =
      Tasks.create(
        c.scope,
        c.group.id,
        %{
          title: "Reusable task",
          accountable_id: c.alex.id,
          assignee_id: c.blair.id,
          backup_id: c.casey.id
        },
        "create"
      )

    {:ok, cancelled} =
      Tasks.update(c.scope, c.group.id, task.id, %{status: "cancelled"}, task.revision, "cancel")

    assert cancelled.status == "cancelled"

    {:ok, reopened} =
      Tasks.update(
        Scope.for_user(c.blair),
        c.group.id,
        task.id,
        %{status: "open"},
        cancelled.revision,
        "reopen"
      )

    assert reopened.status == "open"

    # An old successful command returns its original result, without reverting
    # the current row or adding another historical event.
    {:ok, replay} =
      Tasks.update(c.scope, c.group.id, task.id, %{status: "cancelled"}, task.revision, "cancel")

    assert replay.status == "cancelled"
    assert replay.revision == cancelled.revision
    assert {:ok, %{status: "open", revision: 3}} = Tasks.get(c.scope, c.group.id, task.id)

    {:ok, finished} =
      Tasks.update(
        Scope.for_user(c.casey),
        c.group.id,
        task.id,
        %{status: "done"},
        reopened.revision,
        "finish"
      )

    fields = ~w(id group_id source requester_id accountable_id assignee_id backup_id)a
    assert Map.take(finished, fields) == Map.take(task, fields)
    assert finished.source == "manual"
    assert finished.revision == 4
    {:ok, history} = Tasks.activity(c.scope, c.group.id, task.id)
    assert Enum.sort(Enum.map(history, & &1.revision)) == [1, 2, 3, 4]
    assert Enum.count(Enum.uniq_by(history, & &1.id)) == 4
    assert Enum.find(history, &(&1.command_id == "reopen")).actor_id == c.blair.id
    assert Enum.find(history, &(&1.command_id == "finish")).actor_id == c.casey.id
  end

  test "activity retains a string-keyed frozen task title through later edits and reload", c do
    {:ok, task} = Tasks.create(c.scope, c.group.id, %{title: "Original title"}, "create")

    {:ok, _} =
      Tasks.update(
        c.scope,
        c.group.id,
        task.id,
        %{title: "Current title"},
        task.revision,
        "rename"
      )

    {:ok, events} = Tasks.activity(c.scope, c.group.id)
    created = Enum.find(events, &(&1.command_id == "create"))
    updated = Enum.find(events, &(&1.command_id == "rename"))
    assert created.result["task"]["title"] == "Original title"
    assert updated.result["task"]["title"] == "Current title"
    assert Repo.get!(Event, created.id).result["task"]["title"] == "Original title"
    assert created.result["event"]["id"] == created.id

    assert updated.details["changes"]["title"] == %{
             "from" => "Original title",
             "to" => "Current title"
           }

    assert {:ok, %{title: "Current title"}} = Tasks.get(c.scope, c.group.id, task.id)
  end

  test "replayed create preserves its original result after assignment eligibility changes", c do
    {:ok, grant} = Volunteers.assign_manager(c.admin, c.group.id, c.admin.user.email)
    attrs = %{title: "Stable replay"}
    {:ok, original} = Tasks.create(c.admin, c.group.id, attrs, "manager-create")
    assert original.accountable_id == c.admin.user.id

    :ok = Volunteers.revoke_manager(c.admin, grant.id)
    assert {:ok, replay} = Tasks.create(c.admin, c.group.id, attrs, "manager-create")
    assert replay.id == original.id
    assert replay.accountable_id == original.accountable_id
    assert replay.revision == original.revision

    {:ok, unassigned} = Tasks.create(c.admin, c.group.id, attrs, "admin-create")
    assert unassigned.accountable_id == nil
    {:ok, _grant} = Volunteers.assign_manager(c.admin, c.group.id, c.admin.user.email)
    assert {:ok, replay} = Tasks.create(c.admin, c.group.id, attrs, "admin-create")
    assert replay.id == unassigned.id
    assert replay.accountable_id == nil
    assert Repo.aggregate(Task, :count) == 2
    assert Repo.aggregate(Event, :count) == 2
  end

  test "fresh scope and eligible assignment checks reject foreign, ordinary and revoked accounts",
       c do
    outsider = user_fixture()
    scope = Scope.for_user(outsider)
    {:ok, _} = Volunteers.assign_manager(c.admin, c.foreign.id, outsider.email)
    {:ok, task} = Tasks.create(c.scope, c.group.id, %{title: "Private"}, "create")
    assert {:error, :unauthorized} = Tasks.list(scope, c.group.id)
    assert {:error, :unauthorized} = Tasks.get(scope, c.group.id, task.id)
    assert {:error, :unauthorized} = Tasks.activity(scope, c.group.id)
    assert {:error, :unauthorized} = Tasks.members(scope, c.group.id)
    assert {:error, :unauthorized} = Tasks.create(scope, c.group.id, %{title: "No"}, "no")

    assert {:error, {:validation, _}} =
             Tasks.create(
               c.scope,
               c.group.id,
               %{title: "No", assignee_id: outsider.id},
               "foreign-assignee"
             )

    assert {:error, {:validation, _}} =
             Tasks.create(
               c.scope,
               c.group.id,
               %{title: "No", assignee_id: c.blair.id, backup_id: c.blair.id},
               "same-backup"
             )

    [grant | _] = c.grants
    :ok = Volunteers.revoke_manager(c.admin, grant.id)
    assert {:error, :unauthorized} = Tasks.list(c.scope, c.group.id)
    assert {:error, :unauthorized} = Tasks.get(c.scope, c.group.id, task.id)

    assert {:error, :unauthorized} =
             Tasks.update(c.scope, c.group.id, task.id, %{title: "No"}, task.revision, "revoked")

    assert Repo.aggregate(Task, :count) == 1
    assert Repo.aggregate(Event, :count) == 1
  end

  test "cycles, self dependencies and cross-group prerequisites leave no partial changes", c do
    {:ok, a} = Tasks.create(c.scope, c.group.id, %{title: "A"}, "a")
    {:ok, b} = Tasks.create(c.scope, c.group.id, %{title: "B", prerequisite_ids: [a.id]}, "b")
    {:ok, foreign} = Tasks.create(c.admin, c.foreign.id, %{title: "Foreign"}, "foreign")

    for {key, ids} <- [{"self", [a.id]}, {"cycle", [b.id]}, {"foreign", [foreign.id]}] do
      assert {:error, _} =
               Tasks.update(c.scope, c.group.id, a.id, %{prerequisite_ids: ids}, a.revision, key)
    end

    assert Repo.aggregate(Dependency, :count) == 1
    {:ok, persisted} = Tasks.get(c.scope, c.group.id, a.id)
    assert persisted.prerequisite_ids == []
    assert persisted.revision == a.revision
  end

  test "two database transactions cannot commit opposite prerequisite links" do
    {scope, group, a, b} =
      unboxed(fn ->
        user = user_fixture() |> change(superadmin: true) |> Repo.update!()
        scope = Scope.for_user(user)

        {:ok, group} =
          Volunteers.create_group(scope, %{name: "Concurrent #{Ecto.UUID.generate()}"})

        {:ok, _} = Volunteers.assign_manager(scope, group.id, user.email)
        {:ok, a} = Tasks.create(scope, group.id, %{title: "Concurrent A"}, "a")
        {:ok, b} = Tasks.create(scope, group.id, %{title: "Concurrent B"}, "b")
        {scope, group, a, b}
      end)

    try do
      jobs =
        for {task, prerequisite} <- [{a, b}, {b, a}] do
          Elixir.Task.async(fn ->
            unboxed(fn ->
              Tasks.update(
                scope,
                group.id,
                task.id,
                %{prerequisite_ids: [prerequisite.id]},
                task.revision,
                "link-#{task.id}"
              )
            end)
          end)
        end

      results = Enum.map(jobs, &Elixir.Task.await(&1, 10_000))
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1

      assert Enum.count(
               results,
               &match?({:error, {:validation, %{prerequisite_ids: :cycle}}}, &1)
             ) == 1

      assert unboxed(fn ->
               Repo.aggregate(from(d in Dependency, where: d.group_id == ^group.id), :count)
             end) == 1
    after
      unboxed(fn ->
        Repo.delete_all(from e in Event, where: e.group_id == ^group.id)
        Repo.delete_all(from d in Dependency, where: d.group_id == ^group.id)
        Repo.delete_all(from t in Task, where: t.group_id == ^group.id)
        Repo.delete_all(from m in PauseAiCa.Volunteers.Manager, where: m.group_id == ^group.id)
        Repo.delete_all(from g in PauseAiCa.Volunteers.Group, where: g.id == ^group.id)

        Repo.delete_all(
          from t in PauseAiCa.Accounts.UserToken, where: t.user_id == ^scope.user.id
        )

        Repo.delete_all(from u in PauseAiCa.Accounts.User, where: u.id == ^scope.user.id)
      end)
    end
  end

  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
end
