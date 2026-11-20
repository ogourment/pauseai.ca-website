defmodule PauseAiCaWeb.VolunteerHandoffTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Incubators, Repo, Tasks, Volunteers}
  alias PauseAiCa.Accounts.Scope

  for {first_step, assignment, receipt} <- [
        {"Confirm footage permissions", "Return the captioned protest video",
         "Organizer reviewed credits and approved the cut"},
        {"Confirm the interview deadline", "Brief the spokesperson",
         "Spokesperson confirmed the interview and sent notes"},
        {"Confirm the MP meeting date", "Follow up on the office’s commitments",
         "Office acknowledged receipt of the briefing"},
        {"Approve the application budget", "Submit the funding application",
         "Funder supplied a submission reference"},
        {"Confirm workshop accessibility", "Send workshop materials",
         "Facilitator recorded feedback and assigned the next action"}
      ] do
    test "organizing handoff: #{assignment}" do
      admin =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()
        |> Scope.for_user()

      {:ok, group} = Volunteers.create_group(admin, %{name: "Local organizers"})
      organizer = user_fixture()
      {:ok, _} = Volunteers.assign_manager(admin, group.id, organizer.email)
      owner = Scope.for_user(organizer)
      member = user_fixture()

      Repo.insert!(%Incubators.Membership{
        group_id: group.id,
        user_id: member.id,
        display_name: "Member",
        status: "approved"
      })

      {:ok, prerequisite} =
        Tasks.create(owner, group.id, %{title: unquote(first_step)}, "prepare")

      {:ok, task} =
        Tasks.create(
          owner,
          group.id,
          %{
            title: unquote(assignment),
            assignee_id: member.id,
            prerequisite_ids: [prerequisite.id]
          },
          "assign"
        )

      assert {:error, {:blocked, _}} =
               Tasks.update(
                 owner,
                 group.id,
                 task.id,
                 %{status: "done"},
                 task.revision,
                 "premature"
               )

      {:ok, _} =
        Tasks.update(
          owner,
          group.id,
          prerequisite.id,
          %{status: "done"},
          prerequisite.revision,
          "verified"
        )

      {:ok, manager_view, _} =
        live(
          log_in_user(build_conn(), organizer),
          "/manage/tasks/#{task.id}?group=#{group.id}&locale=en"
        )

      manager_view
      |> form("[data-task-form]", task: %{status: "done", description: unquote(receipt)})
      |> render_submit()

      {:ok, member_view, _} = live(log_in_user(build_conn(), member), "/en/profile")
      assert has_element?(member_view, "#my-group-work li", unquote(assignment))
      assert has_element?(member_view, "#my-group-work li", unquote(receipt))
      assert has_element?(member_view, "#my-group-work li", "Done")
    end
  end

  test "an Ottawa organizer assigns the march edit and the editor finds it on their own profile" do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    admin_scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(admin_scope, %{name: "Ottawa"})
    organizer = user_fixture()
    {:ok, _} = Volunteers.assign_manager(admin_scope, group.id, organizer.email)
    editor = user_fixture(%{name: "Review Editor"})

    membership =
      Repo.insert!(%Incubators.Membership{
        group_id: group.id,
        user_id: editor.id,
        display_name: "Review Editor",
        status: "approved",
        conduct_at: DateTime.utc_now()
      })

    {:ok, _} =
      Incubators.add_responsibility(
        Scope.for_user(organizer),
        group.id,
        membership.id,
        membership.revision,
        %{title: "Video Editor", starts_on: Date.utc_today()}
      )

    {:ok, task_view, _} =
      live(
        log_in_user(build_conn(), organizer),
        "/manage/tasks/new?group=#{group.id}&locale=en"
      )

    task_view
    |> form("[data-task-form]",
      task: %{
        title: "Edit the November 14 march footage",
        assignee_id: editor.id,
        description: "Return the captioned cut to the organizer."
      }
    )
    |> render_submit()

    member_conn = log_in_user(build_conn(), editor)
    {:ok, view, _} = live(member_conn, "/en/profile")
    assert has_element?(view, "#my-group-work", "Video Editor")
    assert has_element?(view, "#my-group-work", "Edit the November 14 march footage")
    assert has_element?(view, "#my-group-work", "Return the captioned cut")
    {:ok, stranger, _} = live(log_in_user(build_conn(), user_fixture()), "/en/profile")
    refute has_element?(stranger, "#my-group-work")
    membership |> Ecto.Changeset.change(status: "removed") |> Repo.update!()
    send(view.pid, :refresh_group_work)
    refute has_element?(view, "#my-group-work")
    {:ok, refreshed, _} = live(member_conn, "/en/profile")
    refute has_element?(refreshed, "#my-group-work")
  end
end
