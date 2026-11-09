if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.GroupAdminTest do
    use AcceptanceHarness.Playwright.Case, async: false

    import Ecto.Query
    import PauseAiCa.AccountsFixtures

    alias PauseAiCa.{Accounts, Incubators, Repo, Volunteers}
    alias PauseAiCa.Incubators.{Event, Membership}
    alias PauseAiCaWeb.{AtddEvidence, AtddNavigation}

    @moduletag :atdd
    @moduletag accept_dialogs: true
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "GROUP-ADMIN-01-#{locale}",
                    title: "Organizer adds existing group accounts · #{language}",
                    tags: ["incubators", "membership", "administration"],
                    roles: ["Superadmin", "Existing member", "Existing manager"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("GROUP-ADMIN-01 · existing account enrollment", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "GROUP-ADMIN-01 organizer adds a member and manager #{locale}", c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      operator =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true, name: "Synthetic organizer")
        |> Repo.update!()

      member = named_user("Synthetic existing member")
      manager = named_user("Synthetic existing manager")
      scope = Accounts.Scope.for_user(operator)
      {:ok, group} = Volunteers.create_group(scope, %{name: "Synthetic organizer group"})

      {:ok, _} =
        Incubators.configure(scope, group.id, %{
          "name_en" => "Synthetic organizer group",
          "name_fr" => "Groupe de démonstration",
          "published" => true,
          "whatsapp_enabled" => false
        })

      browser = c.conn |> login(operator)
      discard_fixture_emails()
      baseline = protected_state()
      identities = identities([operator.id, member.id, manager.id])
      id = "GROUP-ADMIN-01-#{locale}"

      browser =
        browser
        |> visit("/#{locale}")
        |> AtddNavigation.open_section("manage")
        |> capture(
          id,
          "Organizer opens the management menu",
          "/#{locale} · signed-in homepage",
          "Management menu"
        )
        |> click_link(
          "#manage-menu [data-navigation-item='pauseai.groups']",
          tr(locale, "Local groups"),
          exact: true
        )
        |> connected()
        |> assert_has("#incubator-add-member")
        |> capture(
          id,
          "Existing account enrollment form",
          "/#{locale} · open Management menu",
          tr(locale, "Local groups")
        )
        |> add_account(locale, member, "Member")

      member_record = Repo.get_by!(Membership, group_id: group.id, user_id: member.id)

      browser =
        browser
        |> assert_membership(locale, member_record, "member")
        |> add_account(locale, manager, "Manager")

      manager_record = Repo.get_by!(Membership, group_id: group.id, user_id: manager.id)

      browser =
        browser
        |> assert_membership(locale, manager_record, "manager")
        |> assert_has("body", text: tr(locale, "Member added by organizer"))
        |> capture(
          id,
          "Organizer added an existing member and manager",
          "/manage/groups · existing account enrollment form",
          "#{tr(locale, "Add member")} · #{tr(locale, "Manager")}"
        )
        |> visit("/manage/groups?group=#{group.id}&locale=#{locale}")
        |> connected()
        |> assert_membership(locale, member_record, "member")
        |> assert_membership(locale, manager_record, "manager")
        |> assert_has("body", text: tr(locale, "Member added by organizer"))
        |> capture(
          id,
          "Roster and organizer attribution survive reload",
          "/manage/groups · saved roster",
          "Reload the current group page"
        )

      for {record, role} <- [{member_record, "member"}, {manager_record, "manager"}] do
        record = Repo.reload!(record)
        assert record.status == "approved"
        assert record.role == role
        assert is_nil(record.conduct_at)

        event = Repo.get_by!(Event, membership_id: record.id, action: "member_added")
        assert event.group_id == group.id
        assert event.actor_id == operator.id
        assert event.details["source"] == "admin_enrollment"
        assert event.details["role"] == role
        assert event.details["conduct_acknowledged"] == false
        assert event.details["revision"] == record.revision
      end

      assert Repo.aggregate(from(e in Event, where: e.action == "member_added"), :count) == 2
      assert Repo.get_by(Volunteers.Manager, group_id: group.id, user_id: manager.id)
      refute Repo.get_by(Volunteers.Manager, group_id: group.id, user_id: member.id)
      assert Repo.aggregate(Volunteers.Manager, :count) == 1
      assert protected_state() == baseline
      assert identities([operator.id, member.id, manager.id]) == identities
      refute_received {:email, _}

      AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      browser
    end

    defp add_account(browser, locale, user, role) do
      browser
      |> fill_in("#incubator-add-member [name='member[email]']", tr(locale, "Email"),
        with: user.email
      )
      |> select("#incubator-add-member [name='member[role]']", tr(locale, "Role"),
        option: tr(locale, role)
      )
      |> click_button("#incubator-add-member button", tr(locale, "Add member"))
      |> assert_has("#incubator-roster", text: user.name)
    end

    defp assert_membership(browser, locale, record, role) do
      browser
      |> assert_has("#membership-#{record.id}", text: record.display_name)
      |> assert_has("#delegate-#{record.id} select[name='member[role]']", value: role)
      |> assert_has("#membership-#{record.id}",
        text: tr(locale, "Conduct acknowledgement has not been recorded for this account.")
      )
    end

    defp named_user(name),
      do: user_fixture() |> Ecto.Changeset.change(name: name) |> Repo.update!()

    defp login(browser, user) do
      {token, _} = generate_user_magic_link_token(user)

      browser
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp connected(browser), do: assert_has(browser, "[data-phx-main].phx-connected")

    defp protected_state do
      Enum.map(
        [
          Accounts.User,
          Accounts.UserToken,
          PauseAiCa.Newsletters.Subscription,
          PauseAiCa.Newsletters.Batch,
          PauseAiCa.Mail.Batch,
          PauseAiCa.Mail.Draft
        ],
        &{&1, Repo.aggregate(&1, :count)}
      )
    end

    defp identities(ids) do
      from(u in Accounts.User,
        where: u.id in ^ids,
        order_by: u.id,
        select: {u.id, u.email, u.superadmin, u.confirmed_at}
      )
      |> Repo.all()
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
      step = Process.get({:group_admin_step, id}, 0) + 1
      Process.put({:group_admin_step, id}, step)
      filename = "#{id}-#{step}.png"
      evaluate(browser, "location.href", &Process.put(:group_admin_capture_url, &1))
      url = AtddEvidence.safe_url(Process.get(:group_admin_capture_url))
      IO.puts("Capture URL: #{url}")

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "fixture" => "Synthetic local confirmed accounts; no messages or external operations"
      }

      outcome =
        "Group roles persist with organizer attribution and no invented conduct acknowledgement."

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
