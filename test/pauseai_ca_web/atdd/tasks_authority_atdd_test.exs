if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.TasksAuthorityTest do
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
                    id: "TASK-PAI-01-authority-#{locale}",
                    title:
                      "Independent organizer access, stale drafts and revocation · #{language}",
                    tags: ["tasks", "authority", "recovery"],
                    roles: ["Group managers", "Outsider"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("TASK-PAI-01 · authority and recovery", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "TASK-PAI-01 authority and recovery #{locale}", c do
        journey(c, unquote(locale), unquote(width), unquote(height))
      end
    end

    defp journey(c, locale, width, height) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      admin_scope = Accounts.Scope.for_user(admin)
      {:ok, group} = Volunteers.create_group(admin_scope, %{"name" => "Authority group"})
      {:ok, foreign} = Volunteers.create_group(admin_scope, %{"name" => "Other group"})

      [alex, blair, casey, outsider, foreign_manager] =
        for name <- ["Alex", "Blair", "Casey", "Morgan", "Harper"] do
          user_fixture() |> Ecto.Changeset.change(name: name) |> Repo.update!()
        end

      grants =
        for user <- [alex, blair, casey] do
          {:ok, grant} = Volunteers.assign_manager(admin_scope, group.id, user.email)
          {user.id, grant}
        end

      {:ok, _} = Volunteers.assign_manager(admin_scope, foreign.id, foreign_manager.email)
      baseline = counts()
      scope = Accounts.Scope.for_user(alex)

      b =
        c.conn
        |> login(alex)
        |> visit("/manage/tasks/new?group=#{group.id}&locale=#{locale}")
        |> connected()
        |> fill_in(tr(locale, "Title"), with: "Authority task")
        |> capture(locale, "Alex: Add task", "Press Enter in Title to save without a project")
        |> PhoenixTest.Playwright.press("[name='task[title]']", "Enter")
        |> assert_has("#task-editor[data-revision='1']")

      {:ok, [task]} = Tasks.list(scope, group.id)
      task_url = "/manage/tasks/#{task.id}?group=#{group.id}&locale=#{locale}"

      b =
        b
        |> assert_has("#task-editor[data-task-id='#{task.id}']")
        |> capture(
          locale,
          "Alex: Enter saved the task",
          "Open the same task in another browser context"
        )

      config =
        PhoenixTest.Playwright.Config.validate!(
          browser_context_opts: [viewport: %{width: width, height: height}]
        )

      stale =
        PhoenixTest.Playwright.Case.new_session(config, c)
        |> login(alex)
        |> visit(task_url)
        |> connected()
        |> assert_has("#task-editor[data-task-id='#{task.id}'][data-revision='1']")
        |> open_description()
        |> fill_in(tr(locale, "Description"), with: "Alex retained draft", exact: false)

      b =
        switch_browser_identity(b, &login(&1, blair))
        |> visit(task_url)
        |> connected()
        |> assert_has("#task-editor[data-task-id='#{task.id}'][data-revision='1']")
        |> open_description()
        |> fill_in(tr(locale, "Description"), with: "Blair independent update", exact: false)
        |> click_button(tr(locale, "Save"))
        |> assert_has("#task-editor[data-revision='2']")
        |> capture(
          locale,
          "Blair: save through independent identity",
          "Casey opens the persisted task"
        )

      b =
        switch_browser_identity(b, &login(&1, casey))
        |> visit(task_url)
        |> connected()
        |> assert_has("[name='task[description]']", value: "Blair independent update")
        |> select("[name='task[status]']", tr(locale, "Status"),
          exact: false,
          option: tr(locale, "Cancelled")
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("#task-editor[data-status='cancelled'][data-revision='3']")
        |> select("[name='task[status]']", tr(locale, "Status"),
          exact: false,
          option: tr(locale, "Open")
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("#task-editor[data-status='open'][data-revision='4']")
        |> capture(
          locale,
          "Casey: cancel, then reopen",
          "Same task identity and source are retained"
        )

      stale =
        stale
        |> click_button(tr(locale, "Save"))
        |> assert_has("[role=alert]",
          text: tr(locale, "This task changed in another tab. Your draft has been retained.")
        )
        |> assert_has("[name='task[description]']", value: "Alex retained draft")
        |> assert_has("[data-task-form] button[type=submit][disabled]")
        |> capture(
          locale,
          "Alex: stale tab save rejected",
          "Click Keep my draft for review, then Save deliberately"
        )
        |> click_button(tr(locale, "Keep my draft for review"))
        |> refute_has("[data-task-form] button[type=submit][disabled]")
        |> click_button(tr(locale, "Save"))
        |> assert_has("#task-editor[data-revision='5']")
        |> assert_has("[name='task[description]']", value: "Alex retained draft")
        |> capture(
          locale,
          "Alex: retained draft reapplied",
          "Only the explicit reviewed save advances the revision"
        )

      {:ok, persisted} = Tasks.get(scope, group.id, task.id)
      assert persisted.id == task.id and persisted.source == "manual"
      assert persisted.requester_id == alex.id and persisted.status == "open"
      assert persisted.description == "Alex retained draft"
      {:ok, history} = Tasks.activity(scope, group.id, task.id)
      assert Enum.sort(Enum.map(history, & &1.revision)) == [1, 2, 3, 4, 5]
      assert Enum.any?(history, &(&1.actor_id == blair.id))
      assert Enum.count(history, &(&1.actor_id == casey.id)) == 2

      b =
        switch_browser_identity(b, &login(&1, outsider))
        |> visit(task_url)
        |> assert_path("/dashboard")
        |> refute_has("#tasks-workspace")
        |> refute_has("body", text: "Authority task")
        |> capture(
          locale,
          "Morgan: guessed task denied",
          "No task title, counts or Activity are disclosed"
        )

      b =
        switch_browser_identity(b, &login(&1, foreign_manager))
        |> visit("/manage/tasks?group=#{group.id}&view=activity&locale=#{locale}")
        |> assert_path("/dashboard")
        |> refute_has("#tasks-workspace")
        |> refute_has("body", text: "Authority task")
        |> capture(
          locale,
          "Harper: foreign group Activity denied",
          "Existing management authority is scoped to another group"
        )

      b =
        switch_browser_identity(b, &login(&1, blair))
        |> visit(task_url)
        |> connected()
        |> assert_has("#task-editor[data-task-id='#{task.id}'][data-revision='5']")
        |> open_description()
        |> capture(
          locale,
          "Blair: reload the latest saved task",
          "Edit Description, whose wrapping label includes its persisted text"
        )
        |> fill_in(tr(locale, "Description"),
          with: "Revoked write must not persist",
          exact: false
        )
        |> capture(
          locale,
          "Blair: open editor before revocation",
          "An administrator now revokes this manager grant"
        )

      {_, grant} = Enum.find(grants, fn {id, _} -> id == blair.id end)
      :ok = Volunteers.revoke_manager(admin_scope, grant.id)

      b =
        b
        |> click_button(tr(locale, "Save"))
        |> assert_path("/dashboard")
        |> refute_has("#tasks-workspace")
        |> capture(
          locale,
          "Blair: open-session save denied after revocation",
          "Current permission is rechecked without granting authority from task history"
        )

      {:ok, after_revoke} = Tasks.get(scope, group.id, task.id)
      assert after_revoke.revision == 5 and after_revoke.description == "Alex retained draft"
      assert {:error, :unauthorized} = Tasks.activity(Accounts.Scope.for_user(blair), group.id)
      {:ok, final_history} = Tasks.activity(scope, group.id, task.id)

      assert MapSet.new(Enum.map(final_history, & &1.id)) ==
               MapSet.new(Enum.map(history, & &1.id))

      final = counts()
      assert %{final | managers: final.managers + 1} == baseline
      assert Repo.aggregate(PauseAiCa.Tasks.Task, :count) == 1
      assert Repo.aggregate(PauseAiCa.Tasks.Event, :count) == 5

      PhoenixTest.Playwright.evaluate(
        stale,
        "document.documentElement.scrollWidth <= window.innerWidth",
        &assert(&1)
      )

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "TASK-PAI-01-authority-#{locale}"))
      )

      b
    end

    defp login(browser, user) do
      {token, _} = generate_user_magic_link_token(user)

      browser
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp open_description(browser) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.querySelector('[name=\"task[description]\"]').closest('details').open",
        &Process.put(:task_description_open, &1)
      )

      if Process.get(:task_description_open),
        do: browser,
        else: PhoenixTest.Playwright.click(browser, "[data-task-form] details > summary")
    end

    defp connected(browser), do: assert_has(browser, "[data-phx-main].phx-connected")

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp counts do
      %{
        accounts: Repo.aggregate(Accounts.User, :count),
        subscriptions: Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count),
        managers: Repo.aggregate(Volunteers.Manager, :count),
        groups: Repo.aggregate(Volunteers.Group, :count),
        batches: Repo.aggregate(PauseAiCa.Newsletters.Batch, :count),
        deliveries: Repo.aggregate(PauseAiCa.Newsletters.Delivery, :count)
      }
    end

    defp capture(browser, locale, trigger, outcome) do
      id = "TASK-PAI-01-authority-#{locale}"
      step = Process.get({:task_authority_step, locale}, 0) + 1
      Process.put({:task_authority_step, locale}, step)
      filename = "#{id}-#{step}.png"

      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:task_authority_url, &1)
      )

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "control" => trigger,
        "url" => AtddEvidence.safe_url(Process.get(:task_authority_url)),
        "external_systems" =>
          "Synthetic local accounts/database only; no external services or sending"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, trigger, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        trigger,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
