defmodule PauseAiCaWeb.TasksLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.{Repo, Tasks, Volunteers}

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(scope, %{"name" => "Review group"})
    manager = user_fixture(%{name: "Alex"})
    {:ok, grant} = Volunteers.assign_manager(scope, group.id, manager.email)

    %{
      conn: log_in_user(conn, manager),
      scope: Scope.for_user(manager),
      group: group,
      admin: scope,
      grant: grant,
      manager: manager
    }
  end

  test "empty organizer workspace stays open without a misleading access error", c do
    Repo.delete_all(PauseAiCa.Volunteers.Manager)
    Repo.delete_all(PauseAiCa.Volunteers.Group)
    conn = build_conn() |> log_in_user(c.admin.user)
    {:ok, view, _} = live(conn, "/manage/tasks?locale=en")
    assert has_element?(view, "#tasks-no-groups", "No organizer groups yet")
    assert has_element?(view, "a[href='/volunteer-signups?locale=en#group-management']")
    refute has_element?(view, "a", "Add task")
    refute has_element?(view, "#task-group-form")
    send(view.pid, :refresh_access)
    assert has_element?(view, "#tasks-no-groups")
    refute render(view) =~ "This group or task is unavailable."
    assert Repo.aggregate(PauseAiCa.Volunteers.Group, :count) == 0
    assert Repo.aggregate(PauseAiCa.Tasks.Task, :count) == 0
  end

  test "organizer creates a task, reloads it and follows canonical activity", c do
    {:ok, view, _} = live(c.conn, "/manage/tasks?locale=en")
    assert has_element?(view, "#task-list", "No tasks yet")
    view |> element("a", "Add task") |> render_click()
    assert_patch(view, "/manage/tasks/new?group=#{c.group.id}&locale=en")

    view
    |> form("[data-task-form]",
      task: %{
        title: "Confirm the room",
        accountable_id: c.manager.id,
        assignee_id: "",
        backup_id: "",
        due_date: "2026-11-15",
        description: "Ask the venue"
      }
    )
    |> render_submit()

    {:ok, [task]} = Tasks.list(c.scope, c.group.id)
    assert_patch(view, "/manage/tasks/#{task.id}?group=#{c.group.id}&locale=en")
    assert has_element?(view, "[name='task[title]'][value='Confirm the room']")
    {:ok, events} = Tasks.activity(c.scope, c.group.id)
    assert has_element?(view, "#task-event-#{hd(events).id}")
    {:ok, activity, _} = live(c.conn, "/manage/tasks?group=#{c.group.id}&locale=en&view=activity")
    assert has_element?(activity, "#group-task-activity #task-event-#{hd(events).id}")
    assert Repo.aggregate(PauseAiCa.Tasks.Task, :count) == 1
  end

  test "superadmin sees and edits every group's tasks without joining", c do
    {:ok, other} = Volunteers.create_group(c.admin, %{"name" => "Other group"})
    {:ok, task} = Tasks.create(c.scope, c.group.id, %{title: "Room"}, "admin-access")
    before_managers = Repo.aggregate(PauseAiCa.Volunteers.Manager, :count)
    before_memberships = Repo.aggregate(PauseAiCa.Incubators.Membership, :count)
    conn = build_conn() |> log_in_user(c.admin.user)
    {:ok, list, _} = live(conn, "/manage/tasks?locale=en")
    assert has_element?(list, "#task-group-form option[value='#{c.group.id}']")
    assert has_element?(list, "#task-group-form option[value='#{other.id}']")
    {:ok, view, _} = live(conn, "/manage/tasks/#{task.id}?group=#{c.group.id}&locale=en")
    assert has_element?(view, "#task-superadmin-access-note", "full access as a superadmin")
    view |> form("[data-task-form]", task: %{title: "Admin updated room"}) |> render_submit()
    assert {:ok, %{title: "Admin updated room"}} = Tasks.get(c.admin, c.group.id, task.id)
    send(view.pid, :refresh_access)
    assert has_element?(view, "#task-superadmin-access-note")
    assert Repo.aggregate(PauseAiCa.Volunteers.Manager, :count) == before_managers
    assert Repo.aggregate(PauseAiCa.Incubators.Membership, :count) == before_memberships
  end

  test "stale save retains draft and requires deliberate reapplication", c do
    {:ok, task} = Tasks.create(c.scope, c.group.id, %{title: "Room"}, "create")
    {:ok, view, _} = live(c.conn, "/manage/tasks/#{task.id}?group=#{c.group.id}&locale=en")
    {:ok, _} = Tasks.update(c.scope, c.group.id, task.id, %{description: "Other tab"}, 1, "other")
    view |> form("[data-task-form]", task: %{description: "My retained draft"}) |> render_submit()
    assert has_element?(view, "[role=alert]", "another tab")
    assert has_element?(view, "[name='task[description]']", "My retained draft")
    assert has_element?(view, "button[type=submit][disabled]")
    view |> element("button", "Keep my draft for review") |> render_click()
    refute has_element?(view, "button[type=submit][disabled]")
    view |> form("[data-task-form]") |> render_submit()

    assert {:ok, %{description: "My retained draft", revision: 3}} =
             Tasks.get(c.scope, c.group.id, task.id)
  end

  test "invalid backup is inline and revoked manager loses the open page", c do
    {:ok, view, _} = live(c.conn, "/manage/tasks/new?group=#{c.group.id}&locale=en")

    view
    |> form("[data-task-form]",
      task: %{title: "Room", assignee_id: c.manager.id, backup_id: c.manager.id}
    )
    |> render_submit()

    assert render(view) =~ "Choose a different person"
    assert {:ok, []} = Tasks.list(c.scope, c.group.id)
    :ok = Volunteers.revoke_manager(c.admin, c.grant.id)
    send(view.pid, :refresh_access)
    assert_redirect(view, "/dashboard")
  end

  test "superadmin without a manager grant can create an unassigned task", c do
    {:ok, view, _} =
      live(
        log_in_user(build_conn(), c.admin.user),
        "/manage/tasks/new?group=#{c.group.id}&locale=en"
      )

    view |> form("[data-task-form]", task: %{title: "Unassigned admin task"}) |> render_submit()
    assert {:ok, [task]} = Tasks.list(c.admin, c.group.id)
    assert task.accountable_id == nil
    assert task.requester_id == c.admin.user.id
  end

  test "late events from the previous task cannot overwrite a newly opened task", c do
    {:ok, previous} = Tasks.create(c.scope, c.group.id, %{title: "Previous task"}, "previous")
    {:ok, current} = Tasks.create(c.scope, c.group.id, %{title: "Current task"}, "current")
    {:ok, view, _} = live(c.conn, "/manage/tasks/#{previous.id}?group=#{c.group.id}&locale=en")
    old_ref = c.group.id <> "-" <> previous.id
    render_patch(view, "/manage/tasks/#{current.id}?group=#{c.group.id}&locale=en")
    payload = %{"_task_ref" => old_ref, "task" => %{"title" => "Wrong old values"}}
    render_change(view, "validate", payload)
    render_submit(view, "save", payload)
    assert has_element?(view, "[name='task[title]'][value='Current task']")

    assert {:ok, %{title: "Current task", revision: 1}} =
             Tasks.get(c.scope, c.group.id, current.id)

    assert {:ok, %{title: "Previous task", revision: 1}} =
             Tasks.get(c.scope, c.group.id, previous.id)
  end

  test "ordinary accounts and guessed foreign group URLs reveal no task data", c do
    {:ok, _} = Tasks.create(c.scope, c.group.id, %{title: "Private task"}, "create")
    outsider = user_fixture()

    assert {:error, {:redirect, _}} =
             live(
               log_in_user(build_conn(), outsider),
               "/manage/tasks?group=#{c.group.id}&locale=en"
             )
  end
end
