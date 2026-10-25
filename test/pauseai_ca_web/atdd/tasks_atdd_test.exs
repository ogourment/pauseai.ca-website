if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.TasksTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Repo, Tasks, Volunteers}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "TASK-PAI-01-#{locale}",
                    title: "Organizer task and Activity · #{language}",
                    tags: ["tasks", "organizer"],
                    roles: ["Group manager"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("TASK-PAI-01 · approved first organizer task", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "TASK-PAI-01 organizer journey #{locale}", c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      admin_scope = Accounts.Scope.for_user(admin)
      {:ok, group} = Volunteers.create_group(admin_scope, %{"name" => "Synthetic organizers"})

      users =
        for name <- ["Alex", "Blair", "Casey"] do
          user = user_fixture() |> Ecto.Changeset.change(name: name) |> Repo.update!()
          {:ok, _} = Volunteers.assign_manager(admin_scope, group.id, user.email)
          user
        end

      [alex, blair, casey] = users
      scope = Accounts.Scope.for_user(alex)

      baseline =
        {Repo.aggregate(Accounts.User, :count),
         Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count),
         Repo.aggregate(Volunteers.Manager, :count)}

      {token, _} = generate_user_magic_link_token(alex)

      b =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/manage/accounts?locale=#{locale}")
        |> assert_has("[data-phx-main].phx-connected")
        |> capture(locale, "Accounts: preceding screen", "Click Tasks in the Management menu")
        |> click_link(tr(locale, "Tasks"))
        |> assert_has("#task-list",
          text: tr(locale, "No tasks yet. Add the first task for this group.")
        )
        |> capture(locale, "Tasks", "Click Add task")
        |> click_link(tr(locale, "Add task"))
        |> assert_has("[data-task-form]")
        |> fill_in(tr(locale, "Title"), with: "Choose the meeting date")
        |> click_button(tr(locale, "Save"))
        |> assert_has("#task-editor[data-revision='1']")

      {:ok, [prerequisite]} = Tasks.list(scope, group.id)

      b =
        b
        |> click_link(tr(locale, "Back to tasks"))
        |> click_link(tr(locale, "Add task"))
        |> fill_in(tr(locale, "Title"), with: "Confirm the room")
        |> select("[name='task[assignee_id]']", tr(locale, "Assigned to"),
          exact: false,
          option: "Blair"
        )
        |> select("[name='task[backup_id]']", tr(locale, "Backup"), exact: false, option: "Casey")
        |> fill_in(tr(locale, "Due date"), with: "2026-11-15")
        |> select("[name='task[prerequisite_ids][]']", tr(locale, "Prerequisites"),
          exact: false,
          option: "Choose the meeting date"
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("#task-editor[data-revision='1']")
        |> assert_has("[name='task[title]'][value='Confirm the room']")
        |> capture(
          locale,
          "Save task with assignments and prerequisite",
          "Requester, accountable owner, assignee, backup and date persist"
        )

      {:ok, tasks} = Tasks.list(scope, group.id)
      task = Enum.find(tasks, &(&1.title == "Confirm the room"))
      assert task.assignee_id == blair.id
      assert task.backup_id == casey.id
      assert task.prerequisite_ids == [prerequisite.id]

      b =
        b
        |> select("[name='task[status]']", tr(locale, "Status"),
          exact: false,
          option: tr(locale, "In progress")
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("#task-editor[data-revision='2']")
        |> select("[name='task[status]']", tr(locale, "Status"),
          exact: false,
          option: tr(locale, "Done")
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("[role=alert]", text: "Choose the meeting date", exact: false)
        |> capture(
          locale,
          "Attempt completion while blocked",
          "Task stays in progress; prerequisite is linked"
        )
        |> click_link("Choose the meeting date")
        |> assert_has("#task-editor[data-task-id='#{prerequisite.id}']")
        |> assert_has("[name='task[title]'][value='Choose the meeting date']")
        |> select("[name='task[status]']", tr(locale, "Status"),
          exact: false,
          option: tr(locale, "Done")
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("#task-editor[data-status='done'][data-revision='2']")
        |> visit("/manage/tasks/#{task.id}?group=#{group.id}&locale=#{locale}")
        |> assert_has("[data-phx-main].phx-connected")
        |> select("[name='task[status]']", tr(locale, "Status"),
          exact: false,
          option: tr(locale, "Done")
        )
        |> click_button(tr(locale, "Save"))

      b = b |> assert_has("#task-editor[data-status='done'][data-revision='3']")
      {:ok, finished} = Tasks.get(scope, group.id, task.id)
      assert finished.status == "done"

      b =
        b
        |> select("[name='task[assignee_id]']", tr(locale, "Assigned to"),
          exact: false,
          option: "Casey"
        )
        |> select("[name='task[backup_id]']", tr(locale, "Backup"),
          exact: false,
          option: tr(locale, "No backup")
        )
        |> fill_in(tr(locale, "Reason for reassignment"), with: "Blair is unavailable")
        |> click_button(tr(locale, "Save"))

      b = b |> assert_has("#task-editor[data-revision='4']")
      {:ok, events} = Tasks.activity(scope, group.id, task.id)
      event = Enum.find(events, &(&1.action == "delegated"))

      b =
        b
        |> assert_has("#task-event-#{event.id}")
        |> capture(
          locale,
          "Save explicit reassignment",
          "Canonical task history includes the actor and reason"
        )
        |> click_link(tr(locale, "Activity"))
        |> assert_has("#group-task-activity #task-event-#{event.id}")
        |> capture(
          locale,
          "Activity",
          "Same event ID as task history; no duplicate activity store"
        )

      events_before_cycle = Repo.aggregate(PauseAiCa.Tasks.Event, :count)

      b =
        b
        |> visit("/manage/tasks/#{prerequisite.id}?group=#{group.id}&locale=#{locale}")
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#task-editor[data-task-id='#{prerequisite.id}']")
        |> refute_has(
          "select[name='task[prerequisite_ids][]'] option[value='#{prerequisite.id}']"
        )
        |> select("[name='task[prerequisite_ids][]']", tr(locale, "Prerequisites"),
          exact: false,
          option: "Confirm the room"
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("[data-task-form]",
          text: tr(locale, "These prerequisites would create a cycle."),
          exact: false
        )
        |> capture(
          locale,
          "Reject a reverse prerequisite",
          "The cycle is explained inline; no task revision or successful event is added"
        )

      assert {:ok, %{revision: 2, prerequisite_ids: []}} =
               Tasks.get(scope, group.id, prerequisite.id)

      assert Repo.aggregate(PauseAiCa.Tasks.Event, :count) == events_before_cycle

      PhoenixTest.Playwright.evaluate(
        b,
        "document.documentElement.scrollWidth <= window.innerWidth",
        &assert(&1)
      )

      assert baseline ==
               {Repo.aggregate(Accounts.User, :count),
                Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count),
                Repo.aggregate(Volunteers.Manager, :count)}

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "TASK-PAI-01-#{locale}"))
      )

      b
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, locale, trigger, outcome) do
      step = Process.get({:task_step, locale}, 0) + 1
      Process.put({:task_step, locale}, step)
      filename = "TASK-PAI-01-#{locale}-#{step}.png"

      browser =
        PhoenixTest.Playwright.evaluate(
          browser,
          "location.href",
          &Process.put(:task_capture_url, &1)
        )

      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(filename, trigger, outcome, %{
        "scenario_id" => "TASK-PAI-01-#{locale}",
        "url" => AtddEvidence.safe_url(Process.get(:task_capture_url)),
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser)),
        "step" => step,
        "external_systems" => "Synthetic local database only; no providers or messages"
      })

      browser
    end
  end
end
