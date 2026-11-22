if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.TaskMemberTest do
    use AcceptanceHarness.Playwright.Case, async: false

    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Incubators, Repo, Tasks, Volunteers}
    alias PauseAiCaWeb.{AtddEvidence, AtddNavigation}

    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "TASK-MEMBER-01-#{locale}",
                    title: "Assign a newsletter task to an ordinary member · #{language}",
                    tags: ["tasks", "membership"],
                    roles: ["Group manager", "Approved ordinary member"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("TASK-MEMBER-01 · member assignment", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "TASK-MEMBER-01 ordinary member assignment #{locale}", c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = named_user("Synthetic administrator", true)
      manager = named_user("Synthetic organizer")
      member = named_user("Synthetic video editor")
      admin_scope = Accounts.Scope.for_user(admin)
      manager_scope = Accounts.Scope.for_user(manager)
      member_scope = Accounts.Scope.for_user(member)
      {:ok, group} = Volunteers.create_group(admin_scope, %{name: "Synthetic Ottawa group"})
      {:ok, _} = Volunteers.assign_manager(admin_scope, group.id, manager.email)

      {:ok, _} =
        Incubators.configure(admin_scope, group.id, %{
          "name_en" => "Synthetic Ottawa group",
          "name_fr" => "Groupe fictif d’Ottawa",
          "area_served" => "local",
          "fsas" => "H2X",
          "published" => true,
          "whatsapp_enabled" => false
        })

      {:ok, _} = Incubators.add_existing_member(admin_scope, group.id, member.email, "member")
      membership = Repo.get_by!(Incubators.Membership, group_id: group.id, user_id: member.id)
      assert membership.status == "approved"
      assert is_nil(membership.conduct_at)

      {token, _} = generate_user_magic_link_token(manager)

      browser =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")

      discard_fixture_emails()
      baseline = protected_counts()
      id = "TASK-MEMBER-01-#{locale}"

      role_title = if locale == "fr", do: "Montage vidéo", else: "Video Editor"

      browser =
        browser
        |> visit("/manage/groups?group=#{group.id}&locale=#{locale}")
        |> PhoenixTest.Playwright.click("nav a[href*='tab=responsibilities']")
        |> assert_has("[data-phx-main].phx-connected")
        |> click_button(tr(locale, "Add responsibility"))
        |> select("#group-responsibility-form select", tr(locale, "Member"),
          exact: false,
          option: member.name
        )
        |> fill_in(tr(locale, "Responsibility"), with: role_title)
        |> fill_in(tr(locale, "Start date"), with: Date.to_iso8601(Date.utc_today()))
        |> click_button(tr(locale, "Save responsibility"))
        |> assert_has("#group-responsibilities li", text: role_title)

      title =
        if locale == "fr",
          do: "Monter la vidéo de la marche du 14 novembre",
          else: "Edit the November 14 march footage"

      browser =
        browser
        |> visit("/#{locale}")
        |> AtddNavigation.open_section("manage")
        |> capture(id, "Management menu", "/#{locale} · signed-in homepage", "Management menu")
        |> click_link("#manage-menu [data-navigation-item='pauseai.tasks']", tr(locale, "Tasks"),
          exact: true
        )
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#task-list",
          text: tr(locale, "No tasks yet. Add the first task for this group.")
        )
        |> capture(id, "Task list", "/#{locale} · Management menu", tr(locale, "Tasks"))
        |> click_link(tr(locale, "Add task"))
        |> assert_has("[data-task-form]")
        |> fill_in(tr(locale, "Title"), with: title)
        |> select("[data-task-form] [name='task[assignee_id]']", tr(locale, "Assigned to"),
          exact: false,
          option: member.name
        )
        |> assert_has("[data-task-form] [name='task[assignee_id]']", value: member.id)
        |> capture(
          id,
          "Ordinary member selected",
          "/manage/tasks · empty task list",
          "#{tr(locale, "Add task")} · #{tr(locale, "Assigned to")} · #{member.name}"
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("#task-editor[data-revision='1']")

      {:ok, [task]} = Tasks.list(manager_scope, group.id)
      assert task.title == title
      assert task.assignee_id == member.id

      browser =
        browser
        |> visit("/manage/tasks/#{task.id}?group=#{group.id}&locale=#{locale}")
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#task-editor[data-task-id='#{task.id}'][data-revision='1']")
        |> assert_has("[data-task-form] [name='task[title]']", value: title)
        |> assert_has("[data-task-form] [name='task[assignee_id]']", value: member.id)
        |> capture(
          id,
          "Member assignment survives reload",
          "/manage/tasks/new · selected member",
          "#{tr(locale, "Save")} · reload saved task"
        )

      {:ok, persisted} = Tasks.get(manager_scope, group.id, task.id)
      assert persisted.assignee_id == member.id
      assert Repo.reload!(membership) == membership
      refute Repo.reload!(member).superadmin
      refute Repo.get_by(Volunteers.Manager, group_id: group.id, user_id: member.id)
      assert Volunteers.groups(member_scope) == []
      assert {:error, :unauthorized} = Tasks.list(member_scope, group.id)
      assert {:error, :unauthorized} = Tasks.members(member_scope, group.id)
      assert protected_counts() == baseline
      refute_received {:email, _}
      {member_token, _} = generate_user_magic_link_token(member)
      profile = if locale == "fr", do: "/fr/profil", else: "/en/profile"

      viewport =
        if locale == "fr", do: %{width: 390, height: 844}, else: %{width: 1280, height: 900}

      config = PhoenixTest.Playwright.Config.validate!(browser_context_opts: [viewport: viewport])

      PhoenixTest.Playwright.Case.new_session(config, c)
      |> visit("/users/log-in/#{member_token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
      |> visit(profile)
      |> assert_has("#my-group-work", text: title)
      |> assert_has("#my-group-work", text: role_title)
      |> capture(id, "Member reads their assignment", "Signed-in member", "My profile")

      AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      browser
    end

    defp named_user(name, superadmin \\ false),
      do:
        user_fixture()
        |> Ecto.Changeset.change(name: name, superadmin: superadmin)
        |> Repo.update!()

    defp protected_counts do
      Enum.map(
        [
          Accounts.User,
          Accounts.UserToken,
          Volunteers.Manager,
          PauseAiCa.Newsletters.Subscription,
          PauseAiCa.Newsletters.Batch,
          PauseAiCa.Mail.Batch,
          PauseAiCa.Mail.Draft
        ],
        &{&1, Repo.aggregate(&1, :count)}
      )
    end

    defp discard_fixture_emails do
      receive do
        {:email, _} -> discard_fixture_emails()
      after
        0 -> :ok
      end
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, id, title, preceding, control) do
      evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      step = Process.get({:task_member_step, id}, 0) + 1
      Process.put({:task_member_step, id}, step)
      filename = "#{id}-#{step}.png"
      evaluate(browser, "location.href", &Process.put(:task_member_url, &1))
      url = AtddEvidence.safe_url(Process.get(:task_member_url))
      IO.puts("Capture URL: #{url}")

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "fixture" => "Synthetic local accounts and newsletter task; no email delivery"
      }

      outcome = "Approved ordinary member is assigned, with unchanged group and global authority."
      AcceptanceHarness.Evidence.record_pending_step(filename, title, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        title,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
