if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.CrmIntegrationTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PhoenixTest, except: [fill_in: 3, select: 3, select: 4]
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Repo, Volunteers, CRM, Mail}
    alias PauseAiCa.Accounts.{Scope, User}
    alias PauseAiCa.ContactMigration.{Contact, Activity}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @moduletag browser_context_opts: [viewport: %{width: 1280, height: 900}]
    @scenarios [
      %{
        id: "PA-CRM-01",
        title: "Local identity, preserved origins and reversible reconciliation",
        tags: ["contacts", "accounts", "superadmin", "group-manager"],
        roles: ["Superadmin", "Group manager"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "PA-MAIL-01",
        title: "Scoped durable drafts alongside Brevo history",
        tags: ["mail", "accounts", "superadmin", "group-manager"],
        roles: ["Superadmin", "Group manager"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      }
    ]
    setup_all do
      AtddEvidence.reset!("PauseAI CRM integration", @scenarios, %{
        browser: "Chromium",
        viewport: "1280×900"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = confirmed("crm-admin@example.org", %{superadmin: true})
      scope = Scope.for_user(admin)
      {:ok, montreal} = Volunteers.create_group(scope, %{"name" => "Montréal"})
      {:ok, quebec} = Volunteers.create_group(scope, %{"name" => "Québec"})
      manager = confirmed("crm-manager@example.org")
      {:ok, _} = Volunteers.assign_manager(scope, montreal.id, manager.email)
      %{admin: admin, scope: scope, manager: manager, montreal: montreal, quebec: quebec}
    end

    test "PA-CRM-01 reconcile, source replay, safe undo, stale undo and denied access", c do
      id = "PA-CRM-01"

      {:ok, first} =
        CRM.observe(
          c.scope,
          %{"email" => "camille-one@example.org", "name" => "Camille", "city" => "Montréal"},
          "legacy-sheet",
          "row-1"
        )

      {:ok, second} =
        CRM.observe(
          c.scope,
          %{"email" => "camille-two@example.org", "name" => "Camille", "city" => "Québec"},
          "legacy-sheet",
          "row-2"
        )

      legacy =
        Repo.insert!(
          Contact.changeset(%Contact{}, %{
            email: "camille-two@example.org",
            name: "Camille",
            city: "Québec",
            source: "legacy-sheet",
            source_key: "row-2",
            classification: "do_not_contact"
          })
        )

      {:ok, _} = CRM.link_contact(c.scope, legacy)

      Repo.insert!(
        Activity.changeset(%Activity{}, %{
          contact_id: legacy.id,
          actor_user_id: c.admin.id,
          action: "imported",
          details: %{}
        })
      )

      flush_fixture_emails()
      before_users = Repo.aggregate(User, :count)

      b =
        sign_in(c.conn, c.admin)
        |> visit("/admin/dashboard?locale=en")
        |> click_link("Contacts")
        |> assert_has("#crm-directory")
        |> refute_has("#announcement-banners")
        |> refute_has("#campaign-prompt")
        |> capture(
          id,
          "Open Administration then Contacts",
          "Two local records; no accounts created"
        )

      b =
        b
        |> click_link("camille-one@example.org")
        |> click_button("Reconcile")
        |> select("Other person", option: "camille-two@example.org")
        |> click_button("Compare")
        |> assert_has("#crm-comparison", text: "Québec")
        |> capture(
          id,
          "Compare the two records",
          "Read-only city conflict and two address choices"
        )

      assert Repo.aggregate(PhoenixCRM.Person, :count) == 2
      assert Repo.aggregate(PhoenixCRM.Merge, :count) == 0

      b =
        b
        |> select("#crm-comparison select[name='resolution[city]']", "City", option: "Montréal")
        |> select("Preferred address", option: "camille-one@example.org")
        |> click_button("Confirm reconciliation")
        |> assert_has("#crm-addresses", text: "camille-two@example.org")
        |> assert_has("#crm-origins", text: "do_not_contact")
        |> capture(
          id,
          "Confirm explicit city and preferred address",
          "Both origins and legacy activity survive under one identity"
        )

      assert {:ok, %{person: %{id: canonical}}} = CRM.get(c.scope, second.person.id)
      assert canonical == first.person.id
      assert Repo.get!(Contact, legacy.id).classification == "do_not_contact"
      assert length(CRM.legacy_activities(c.scope, canonical)) == 1

      assert {:ok, _} =
               CRM.observe(
                 c.scope,
                 %{"email" => "camille-two@example.org", "city" => "Changed source"},
                 "legacy-sheet",
                 "row-2"
               )

      assert {:ok, %{person: %{city: "Montréal"}}} = CRM.get(c.scope, canonical)
      assert Repo.aggregate(PhoenixCRM.Person, :count) == 2

      b =
        b
        |> click_button("Undo reconciliation")
        |> assert_has("#crm-addresses", text: "camille-one@example.org")
        |> capture(
          id,
          "Undo an untouched reconciliation",
          "Two original identities restored without losing source links"
        )

      assert {:ok, %{person: %{id: restored}}} = CRM.get(c.scope, second.person.id)
      assert restored == second.person.id

      b
      |> click_button("Reconcile")
      |> select("Other person", option: "camille-two@example.org")
      |> click_button("Compare")
      |> select("#crm-comparison select[name='resolution[city]']", "City", option: "Montréal")
      |> select("Preferred address", option: "camille-one@example.org")
      |> click_button("Confirm reconciliation")
      |> fill_in("Name", with: "Camille reviewed")
      |> click_button("Save contact")
      |> click_button("Undo reconciliation")
      |> assert_has("#crm-error", text: "changed")
      |> capture(
        id,
        "Edit the merged person then attempt undo",
        "Unsafe undo refused and human correction retained"
      )

      assert {:ok, %{person: %{name: "Camille reviewed"}}} = CRM.get(c.scope, second.person.id)

      member =
        sign_in(new_device(c), c.manager)
        |> visit("/admin/contacts/#{first.person.id}?locale=en")
        |> refute_has("#crm-record")

      capture(
        member,
        id,
        "Attempt historical contact access as group manager",
        "Private directory and reconciliation are denied"
      )

      assert {:error, :unauthorized} = CRM.get(Scope.for_user(c.manager), first.person.id)
      assert Repo.aggregate(User, :count) == before_users
      refute_receive {:email, _}
      AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
    end

    test "PA-MAIL-01 scoped selection, isolated drafts, repeat generation, recovery and revocation",
         c do
      id = "PA-MAIL-01"

      member =
        confirmed("draft-montreal@example.org", %{
          name: "Camille",
          city: "Montréal",
          organizing_group_id: c.montreal.id
        })

      other =
        confirmed("draft-quebec@example.org", %{
          name: "Québec person",
          organizing_group_id: c.quebec.id
        })

      blocked = confirmed("draft-blocked@example.org", %{organizing_group_id: c.montreal.id})

      Repo.insert!(
        Contact.changeset(%Contact{}, %{
          email: blocked.email,
          source: "review",
          classification: "do_not_contact"
        })
      )

      flush_fixture_emails()
      scope = Scope.for_user(c.manager)
      assert {:error, :unauthorized} = Mail.recipient(scope, other.id)
      assert {:error, :ineligible} = Mail.recipient(scope, blocked.id)

      b =
        sign_in(c.conn, c.manager)
        |> visit("/manage/accounts/#{member.id}?locale=en")
        |> click_link("Compose")
        |> click_button("Start draft")
        |> assert_has("#mail-workspace", text: member.email)
        |> refute_has("#announcement-banners")
        |> refute_has("#campaign-prompt")
        |> capture(
          id,
          "Open a Montréal account then Compose",
          "Owner-scoped local draft with eligible account; Brevo history remains reachable"
        )

      b =
        b
        |> fill_in("Subject template", with: "Hello {{name}}")
        |> fill_in("Message template · Markdown",
          with: "## Hello {{name}}\nMeet in {{city}}. {{missing}}"
        )
        |> click_button("Generate drafts")
        |> assert_has("#mail-error", text: "missing")
        |> capture(
          id,
          "Generate with an unresolved variable",
          "Missing variable shown; no partial generation"
        )

      assert Repo.aggregate(Mail.Draft, :count) == 0

      b =
        b
        |> fill_in("Message template · Markdown", with: "## Hello {{name}}\nMeet in {{city}}.")
        |> click_button("Generate drafts")
        |> assert_has("#mail-drafts", text: "Hello Camille")
        |> capture(
          id,
          "Generate the recipient draft",
          "Merged subject and Markdown saved independently"
        )

      draft = Repo.one!(Mail.Draft)

      b =
        b
        |> click_link("Edit draft")
        |> fill_in("Message · Markdown", with: "## Personally reviewed\nKeep this edit.")
        |> click_button("Save draft")
        |> assert_has("#mail-save-status", text: "Saved")
        |> click_button("Generate drafts")
        |> assert_has("#mail-draft-source", value: "## Personally reviewed\nKeep this edit.")
        |> capture(
          id,
          "Edit, save and generate again",
          "Repeat generation keeps the edited draft and creates no duplicate"
        )

      assert Repo.aggregate(Mail.Draft, :count) == 1
      assert Repo.get!(Mail.Draft, draft.id).source =~ "Keep this edit."

      b =
        evaluate(
          b,
          "window.crmOpen = window.open.bind(window); window.open = (...args) => {window.crmPreview = window.crmOpen(...args); return window.crmPreview;}; true"
        )

      b =
        b
        |> click_button("#mail-draft-form [data-pme-preview]", "Preview ↗")
        |> assert_has("#mail-draft .pme-status", text: "Preview updated")

      evaluate(
        b,
        "({separate:window.crmPreview && window.crmPreview !== window, sandbox:window.crmPreview.document.querySelector('iframe').getAttribute('sandbox'), html:window.crmPreview.document.querySelector('iframe').srcdoc})",
        &Process.put(:actual_preview, &1)
      )

      assert Process.get(:actual_preview)["separate"]
      assert Process.get(:actual_preview)["sandbox"] == ""
      assert Process.get(:actual_preview)["html"] =~ "Personally reviewed"

      b
      |> capture(
        id,
        "Open the separate live preview window",
        "Actual sandboxed preview contains the edited Markdown"
      )

      batch = Repo.get!(Mail.Batch, draft.batch_id)

      resumed =
        sign_in(new_device(c), c.manager)
        |> visit("/manage/mail/#{batch.id}?locale=en&draft=#{draft.id}")
        |> assert_has("#mail-draft-source", value: "## Personally reviewed\nKeep this edit.")
        |> capture(
          id,
          "Resume on another browser identity",
          "Durable source and recipient snapshot survive sign-in"
        )

      sign_in(new_device(c), c.admin)
      |> visit("/manage/mail/#{batch.id}?locale=en")
      |> refute_has("#mail-workspace")

      assert {:error, :unauthorized} = Mail.get(c.scope, batch.id)
      {:ok, own} = Mail.create(c.scope, member.id)
      assert own.id != batch.id

      {:ok, %{record: _}} =
        PhoenixCRM.import(CRM.context(), c.scope, %{"email" => "historical-only@example.org"}, %{
          source: "archive",
          external_key: "old",
          observed_at: DateTime.utc_now()
        })
        |> then(fn {:ok, record} -> {:ok, %{record: record}} end)

      assert {:ok, results} = PauseAiCa.Mail.ContactSource.search(scope, "historical-only", [])
      assert results == []

      Application.put_env(:pauseai_ca, :brevo_history_req_options,
        plug: &PauseAiCa.BrevoHistoryStub.call/2
      )

      Application.put_env(:pauseai_ca, :history_test_failure, true)

      on_exit(fn ->
        Application.delete_env(:pauseai_ca, :brevo_history_req_options)
        Application.delete_env(:pauseai_ca, :history_test_failure)
      end)

      resumed
      |> click_link("Account and Brevo history")
      |> click_button("Refresh history")
      |> assert_has("#history-campaigns", text: "Brevo is limiting requests")
      |> capture(
        id,
        "Refresh Brevo history during a provider outage",
        "Provider failure is visible while the local saved draft remains intact"
      )

      resumed =
        resumed
        |> visit("/manage/mail/#{batch.id}?locale=en&draft=#{draft.id}")
        |> assert_has("#mail-draft-source", value: "## Personally reviewed\nKeep this edit.")

      manager_assignment =
        Repo.get_by!(PauseAiCa.Volunteers.Manager, user_id: c.manager.id, group_id: c.montreal.id)

      :ok = Volunteers.revoke_manager(c.scope, manager_assignment.id)

      resumed
      |> fill_in("Message · Markdown", with: "Forbidden late edit")
      |> click_button("Save draft")
      |> assert_has("#mail-error", text: "access")
      |> capture(
        id,
        "Revoke group access then attempt a draft save",
        "Fresh authorization denies the write and stored draft stays intact"
      )

      assert Repo.get!(Mail.Draft, draft.id).source =~ "Keep this edit."
      refute_receive {:email, _}
      AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
    end

    defp flush_fixture_emails do
      receive do
        {:email, _} -> flush_fixture_emails()
      after
        0 -> :ok
      end
    end

    defp confirmed(email, attrs \\ %{}),
      do:
        user_fixture(%{email: email})
        |> Ecto.Changeset.change(Map.put(attrs, :confirmed_at, DateTime.utc_now(:second)))
        |> Repo.update!()

    defp sign_in(b, user) do
      {token, _} = generate_user_magic_link_token(user)

      b
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp new_device(c),
      do:
        PhoenixTest.Playwright.Case.new_session(
          PhoenixTest.Playwright.Config.validate!(
            browser_context_opts: [viewport: %{width: 1280, height: 900}]
          ),
          c
        )

    defp select(b, label, opts),
      do: PhoenixTest.select(b, label, Keyword.put(opts, :exact, false))

    defp select(b, selector, label, opts),
      do: PhoenixTest.select(b, selector, label, Keyword.put(opts, :exact, false))

    defp fill_in(b, label, opts),
      do: b |> assert_has("[data-phx-main].phx-connected") |> PhoenixTest.fill_in(label, opts)

    defp capture(b, id, trigger, outcome) do
      step = Process.get({:step, id}, 0) + 1
      Process.put({:step, id}, step)
      filename = "#{id}-#{String.pad_leading(to_string(step), 2, "0")}.png"
      title = Enum.find(@scenarios, &(&1.id == id)).title

      metadata = %{
        "scenario_id" => id,
        "step" => to_string(step),
        "user" => "Superadmin / Group manager",
        "click_target" => trigger,
        "external_systems" =>
          "Synthetic local DB and existing synthetic Brevo fixtures; no provider send"
      }

      AcceptanceHarness.Evidence.record_pending_step(
        filename,
        title,
        trigger <> " → " <> outcome,
        metadata
      )

      started = System.monotonic_time(:millisecond)
      b = AtddEvidence.capture_full_page(b, filename)
      evaluate(b, "location.href", &Process.put(:crm_url, &1))

      AtddEvidence.record_step(
        filename,
        title,
        trigger <> " → " <> outcome,
        Map.merge(metadata, %{
          "duration_ms" => System.monotonic_time(:millisecond) - started,
          "current_url" => AtddEvidence.safe_url(Process.get(:crm_url)),
          "geometry" => Process.get(:evidence_geometry),
          "language" => "English",
          "device" => "Desktop"
        })
      )

      b
    end
  end
end
