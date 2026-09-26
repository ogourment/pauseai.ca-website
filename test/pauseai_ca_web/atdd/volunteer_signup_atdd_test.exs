if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.VolunteerSignupTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PhoenixTest, except: [fill_in: 3, select: 3, select: 4]
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Repo, Volunteers}
    alias PauseAiCa.Accounts.Scope
    alias PauseAiCa.Volunteers.{Batch, Invitation, Profile, Signup, Manager}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @moduletag browser_context_opts: [viewport: %{width: 1280, height: 900}]
    @moduletag accept_dialogs: true
    @scenarios Enum.map(
                 [
                   {"VOL-10", "Accounts directory, single creation and scoped management",
                    "English"},
                   {"VOL-01", "Sheet to account and first sign-in", "English"},
                   {"VOL-02", "CSV correction in an assigned group", "French"},
                   {"VOL-03", "Existing accounts, exclusions and deliberate resend", "English"},
                   {"VOL-04", "Manager scope and revocation", "English"},
                   {"VOL-05", "Recover rejected and ambiguous invitations", "English"},
                   {"VOL-06", "Saved draft, reconnect and single confirmation", "English"},
                   {"VOL-07", "Ten immediate signup invitations", "English"},
                   {"VOL-08", "Row override survives changed default and another sign-in",
                    "English"},
                   {"VOL-09", "Short standalone profile forms resume on another device",
                    "English"}
                 ],
                 fn {id, title, language} ->
                   %{
                     id: id,
                     title: title,
                     language: language,
                     device: "Desktop",
                     roles: ["Organizer / volunteer"],
                     source_file: __ENV__.file
                   }
                 end
               )

    setup_all do
      AtddEvidence.reset!("Volunteer signup acceptance evidence", @scenarios, %{
        browser: "Chromium",
        platform: "Local / CI",
        viewport: "1280×900"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      mailer = Application.get_env(:pauseai_ca, PauseAiCa.Mailer)
      mailbox = Application.get_env(:swoosh, :shared_test_process)
      Application.put_env(:swoosh, :shared_test_process, self())
      Application.put_env(:pauseai_ca, PauseAiCa.Mailer, adapter: PauseAiCa.VolunteerMailAdapter)
      Application.put_env(:pauseai_ca, :volunteer_test_outcomes, %{})

      on_exit(fn ->
        Application.put_env(:pauseai_ca, PauseAiCa.Mailer, mailer)
        Application.put_env(:swoosh, :shared_test_process, mailbox)
        Application.delete_env(:pauseai_ca, :volunteer_test_outcomes)
      end)

      admin =
        user_fixture(%{email: "organizer@example.org"})
        |> Ecto.Changeset.change(superadmin: true, confirmed_at: DateTime.utc_now(:second))
        |> Repo.update!()

      scope = Scope.for_user(admin)
      {:ok, montreal} = Volunteers.create_group(scope, %{"name" => "Montréal"})
      {:ok, quebec} = Volunteers.create_group(scope, %{"name" => "Québec"})
      %{admin: admin, scope: scope, montreal: montreal, quebec: quebec}
    end

    test "VOL-01 spreadsheet, review, real invitation, volunteer ownership and admin result", c do
      id = "VOL-01"

      b =
        open_workspace(c.conn, c.admin, id)
        |> select("Default incubator / group", option: "Montréal")
        |> paste(5, "sheet")

      b =
        b
        |> cell(1, "name", "Camille Exemple")
        |> click_button("Add row")
        |> assert_has("#signup-grid tbody tr", count: 6)

      b =
        b
        |> click("#signup-grid tbody tr:last-child [phx-click='remove-row']")
        |> capture(
          id,
          "Edit a name, add and remove a row",
          "Five separate names, emails, postal codes, group scopes and private notes"
        )

      b = review(b, 5, id)
      assert Repo.aggregate(Signup, :count) == 0
      assert Repo.aggregate(Invitation, :count) == 0
      b = confirm(b, id)
      assert Repo.aggregate(Signup, :count) == 5
      emails = Enum.map(1..5, &invitation("sheet#{&1}@example.org"))
      refute Enum.any?(emails, &(&1.html_body =~ "private-sheet"))

      recipient =
        new_device(c)
        |> show_email(hd(emails))
        |> capture(
          id,
          "Open the captured invitation",
          "Actual single-recipient bilingual message and sign-in action"
        )
        |> sign_in_email()

      recipient =
        recipient
        |> account_menu()
        |> click_link("My profile")
        |> assert_has("input[value='Camille Exemple']")
        |> assert_has("input[value='H2X1Y4']")
        |> capture(
          id,
          "Follow delivered sign-in and open My profile",
          "Imported name and postal code belong to the confirmed account"
        )

      assert Accounts.get_user_by_email("sheet1@example.org").confirmed_at
      refute Accounts.get_user_by_email("sheet1@example.org").local_updates

      b
      |> click_button("Refresh results")
      |> assert_has("#batch-result", text: "Email confirmed")
      |> capture(
        id,
        "Refresh organizer results",
        "Confirmation is separate from provider acceptance"
      )

      recipient
      |> refute_has("body", text: "private-sheet")
      |> refute_has("#account-management-links")

      open_workspace(new_device(c, 390), c.admin, id)
      |> capture(
        id,
        "Open signup workspace on a narrow screen",
        "Grouped account navigation remains usable at 390 pixels"
      )

      assert Repo.aggregate(Manager, :count) == 0
      finish(id)
    end

    test "VOL-08 per-row group overrides survive changed defaults and another device", c do
      id = "VOL-08"
      manager = manager(c, [c.montreal, c.quebec])

      b =
        open_workspace(c.conn, manager, id)
        |> select("Default incubator / group", option: "Montréal")
        |> paste(5, "override")

      b =
        b
        |> select("#signup-grid tbody tr:nth-child(2) select", "Row group", option: "Québec")
        |> capture(
          id,
          "Override the second row to Québec",
          "One explicit override and four inherited Montréal groups"
        )

      b =
        b
        |> select("Default incubator / group", option: "Québec")
        |> assert_has("#signup-grid tbody tr:nth-child(2)", text: "Override")
        |> capture(id, "Change the batch default", "The explicit override remains explicit")

      b
      |> select("Default incubator / group", option: "Montréal")
      |> click_button("Select eligible rows")
      |> fill_in("Source label", with: "Override sheet")
      |> click_button("Save draft")
      |> assert_has("body", text: "Draft saved")

      batch = Repo.one!(Batch)

      b =
        open_workspace(new_device(c), manager, id)
        |> click_link("Override sheet · Draft")
        |> capture(
          id,
          "Sign in on another device and resume",
          "Saved selection, default and override restored"
        )
        |> review(5, id)
        |> confirm(id)

      assert Enum.frequencies_by(
               Volunteers.results(Scope.for_user(manager), batch.id),
               & &1.group_id
             ) == %{c.montreal.id => 4, c.quebec.id => 1}

      for n <- 1..5, do: invitation("override#{n}@example.org")
      b |> assert_has("#batch-result", text: "Québec")
      restricted = manager(c, [c.montreal], "restricted@example.org")

      bad =
        open_workspace(new_device(c), restricted, id)
        |> paste(1, "forbidden", "Québec")
        |> click_button("Review and invite")

      bad
      |> assert_has("body", text: "Draft not saved")
      |> capture(
        id,
        "Attempt a Québec row as a Montréal-only manager",
        "Server denies saving or confirming the out-of-scope row"
      )

      refute Accounts.get_user_by_email("forbidden1@example.org")
      finish(id)
    end

    test "VOL-09 optional profile wizard, another device and volunteer editing without Catalyse",
         c do
      id = "VOL-09"

      b =
        open_workspace(c.conn, c.admin, id)
        |> select("Default incubator / group", option: "Montréal")
        |> paste(1, "profile")
        |> click_button("Optional details")

      b =
        b
        |> select("Preferred contact method", option: "Signal")
        |> fill_in("Signal", with: "+1 555 010 1234")
        |> fill_in("City", with: "Montréal")
        |> click_button("Next")
        |> fill_in("Hours available per week", with: "4")
        |> fill_in("Skills and proficiency", with: "Organizing / Facilitation: advanced")
        |> capture(
          id,
          "Enter contact and contribution in separate short steps",
          "Local fields preserve channel, city, integer hours and named skill proficiency"
        )

      b |> click_button("Save and exit") |> refute_has("#row-details")

      b =
        open_workspace(new_device(c), c.admin, id)
        |> click_link("Untitled batch · Draft")
        |> assert_has("#profile_availability_hours_per_week[value='4']")
        |> capture(id, "Resume from another browser", "Contribution step and values restored")
        |> click_button("Back to rows")
        |> review(1, id)
        |> confirm(id)

      recipient =
        new_device(c)
        |> show_email(invitation("profile1@example.org"))
        |> sign_in_email()
        |> account_menu()
        |> click_link("Volunteer profile")
        |> assert_has("#profile_signal_number[value='+1 555 010 1234']")
        |> capture(
          id,
          "Volunteer opens their imported profile",
          "Private organizer notes are absent"
        )

      recipient =
        recipient
        |> fill_in("Contact instructions", with: "Evenings")
        |> click_button("Save and exit")
        |> assert_path("/dashboard")
        |> assert_has("#suggested-next-step")

      recipient =
        recipient
        |> account_menu()
        |> click_link("Volunteer profile")
        |> assert_has("#profile_contact_notes", text: "Evenings")
        |> click_button("Next")
        |> click_button("Next")
        |> click_button("Save profile")
        |> capture(
          id,
          "Resume and finish personal profile",
          "Profile is persisted locally without external linkage"
        )

      user = Accounts.get_user_by_email("profile1@example.org")
      profile = Repo.get_by!(Profile, user_id: user.id)
      assert profile.details["availability_hours_per_week"] == 4

      assert [%{"name" => "Facilitation", "proficiency" => "advanced"}] =
               profile.details["skills"]

      refute Map.has_key?(profile.details, "notes")
      refute Map.has_key?(profile.details, "catalyse_id")
      recipient |> refute_has("body", text: "private-profile")
      b |> assert_has("#batch-result")
      finish(id)
    end

    test "VOL-02 French CSV correction, mapping and scoped results", c do
      id = "VOL-02"
      manager = manager(c, [c.montreal])

      b =
        open_workspace(c.conn, manager, id)
        |> account_menu()
        |> click_link("Passer au français")
        |> assert_has("h1", text: "Ajouter plusieurs comptes")

      b =
        b
        |> assert_has("[data-phx-main].phx-connected")
        |> upload("Fichier CSV", "test/fixtures/volunteer_signups.csv")
        |> click_button("Associer les colonnes CSV")
        |> capture(
          id,
          "Upload UTF-8 CSV with French headers",
          "Editable destination mapping preserves the original columns"
        )
        |> click_button("Ouvrir les lignes modifiables")

      b =
        b
        |> assert_has("#signup-grid", text: "Saisissez une adresse courriel valide.")
        |> assert_has("#signup-grid", text: "Entrez un code postal canadien complet.")
        |> capture(
          id,
          "Inspect imported rows and validation",
          "Accents, commas and multiline organizer comments remain intact"
        )

      b =
        PhoenixTest.fill_in(
          b,
          "#signup-grid tbody tr:nth-child(1) input[name$='[email]']",
          "Courriel",
          with: "csv1@example.org"
        )

      b =
        PhoenixTest.fill_in(
          b,
          "#signup-grid tbody tr:nth-child(1) input[name$='[postal_code]']",
          "Code postal",
          with: "H2X 1Y4"
        )

      b =
        b
        |> fill_in("Libellé de la source", with: "Feuille bénévoles")
        |> click_button("Sélectionner les lignes admissibles")
        |> click_button("Vérifier et inviter")
        |> assert_has("#signup-review", text: "3 bénévoles sélectionnés")
        |> capture(
          id,
          "Correct invalid cells and review three eligible rows",
          "Email remains required; optional missing fields do not prevent signup"
        )
        |> click_button("Créer les comptes et envoyer les invitations")
        |> assert_has("#batch-result", text: "Acceptée par le fournisseur de courriel")
        |> reload_page()
        |> capture(id, "Confirm and reload", "Montréal scope and per-row outcomes persist")

      assert Repo.aggregate(Signup, :count) == 3
      for n <- 1..3, do: invitation("csv#{n}@example.org")
      assert Repo.one!(Batch).source == "Feuille bénévoles"
      assert Enum.all?(Repo.all(Signup), &(&1.group_id == c.montreal.id))
      assert Enum.all?(Repo.all(PauseAiCa.Volunteers.Event), &(&1.actor_id == manager.id))
      b |> assert_has("#batch-result", text: "Montréal")
      finish(id)
    end

    test "VOL-03 reconcile existing account, repeated addresses and suppression", c do
      id = "VOL-03"

      b =
        open_workspace(c.conn, c.admin, id)
        |> select("Default incubator / group", option: "Montréal")
        |> paste(1, "prior")
        |> fill_in("Source label", with: "Prior batch")
        |> review(1, id)
        |> confirm(id)

      invitation("prior1@example.org")

      existing =
        user_fixture(%{email: "existing@example.org"})
        |> Ecto.Changeset.change(
          name: "Existing verified name",
          confirmed_at: DateTime.utc_now(:second)
        )
        |> Repo.update!()

      {:ok, _} =
        PauseAiCa.ContactMigration.import_selected(
          [%{"email" => "blocked@example.org", "status" => "do_not_contact"}],
          "synthetic.csv",
          "ATDD",
          c.admin
        )

      b =
        b
        |> click_button("New batch")
        |> upload("CSV file", "test/fixtures/volunteer_existing.csv")
        |> click_button("Map CSV columns")
        |> click_button("Open editable rows")
        |> assert_has("#signup-grid", text: "Previously imported")
        |> assert_has("#signup-grid", text: "Do not contact")
        |> capture(
          id,
          "Paste previous, case-varied, existing, new and suppressed rows",
          "Exclusions are visible before selection"
        )
        |> review(2, id)
        |> confirm(id)

      invitation("existing@example.org")
      invitation("fresh@example.org")
      assert Accounts.get_user!(existing.id).name == "Existing verified name"
      assert Repo.aggregate(Signup, :count) == 3

      b =
        b
        |> reload_page()
        |> capture(id, "Reload the result", "No new account or invitation is created")

      assert Repo.aggregate(Invitation, :count) == 3

      b =
        b
        |> click_button("New batch")
        |> upload("CSV file", "test/fixtures/volunteer_existing.csv")
        |> click_button("Map CSV columns")
        |> click_button("Open editable rows")
        |> click_button("Select eligible rows")
        |> assert_has("#signup-selected", text: "0 selected")
        |> capture(
          id,
          "Repeat the sheet",
          "Previously imported and suppressed addresses cannot send automatically"
        )

      batch =
        Repo.all(Batch)
        |> Enum.find(&Enum.any?(&1.rows, fn r -> r["email"] == "fresh@example.org" end))

      b = b |> click_link("Prior batch · Confirmed")

      b
      |> assert_has("[phx-click='resend']")
      |> capture(
        id,
        "Open a completed batch",
        "A deliberate resend is a separate explicit action"
      )

      prior = Repo.get_by!(Signup, email: "prior1@example.org")
      attempt = Repo.get_by!(Invitation, signup_id: prior.id)

      b
      |> click_button("Resend invitation")
      |> assert_has("#batch-result", text: "Resend requested")
      |> capture(
        id,
        "Explicitly request another invitation",
        "Resend has its own audited attempt"
      )

      assert {:error, :not_retryable} = Volunteers.resend(c.scope, attempt.id)
      invitation("prior1@example.org")

      assert Enum.any?(
               Volunteers.events(c.scope, prior.batch_id),
               &(&1.action == "invitation_resend_requested")
             )

      assert Repo.get!(Batch, batch.id).state == "confirmed"
      finish(id)
    end

    test "VOL-04 manager assignment UI, forbidden scope and revoked confirmation", c do
      id = "VOL-04"

      user =
        user_fixture(%{email: "scoped@example.org"})
        |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
        |> Repo.update!()

      admin =
        open_workspace(c.conn, c.admin, id)
        |> select("Default incubator / group", option: "Québec")
        |> paste(1, "quebec")
        |> review(1, id)
        |> confirm(id)

      invitation("quebec1@example.org")
      other_batch = Repo.one!(Batch)

      admin =
        admin
        |> click_button("New batch")
        |> click("#group-management summary")
        |> select("Group to manage", option: "Montréal")
        |> fill_in("Manager email", with: user.email)
        |> click_button("Assign manager")
        |> capture(
          id,
          "Assign a confirmed account to Montréal",
          "The management UI records the explicit scope"
        )

      b =
        open_workspace(new_device(c), user, id)
        |> evaluate(
          "document.querySelector('#signup-default-group').value",
          &assert(&1 == c.montreal.id)
        )
        |> paste(1, "scoped")
        |> review(1, id)

      batch = Repo.get_by!(Batch, owner_id: user.id)
      outsider = open_workspace(new_device(c), user, id)

      outsider
      |> visit("/volunteer-signups?batch=#{other_batch.id}")
      |> refute_has("body", text: "private-quebec")
      |> capture(
        id,
        "Attempt the other group's batch URL",
        "Private Québec notes are unavailable"
      )

      forbidden =
        open_workspace(new_device(c), user, id)
        |> paste(1, "other", "Québec")
        |> click_button("Review and invite")
        |> assert_has("body", text: "Draft not saved")
        |> capture(
          id,
          "Attempt another group's row",
          "No account, assignment or invitation can be created"
        )

      refute Accounts.get_user_by_email("other1@example.org")

      admin
      |> capture(
        id,
        "Return to group management",
        "The original administrator session retains management controls"
      )
      |> click_button("Revoke manager")
      |> capture(id, "Revoke access while a review is open", "The assignment is removed")

      b
      |> click_button("Create accounts and send invitations")
      |> assert_has("body", text: "not authorized")
      |> capture(
        id,
        "Try confirmation after revocation",
        "Fresh authorization denies all side effects"
      )

      assert Repo.aggregate(Signup, :count) == 1
      assert Repo.aggregate(Invitation, :count) == 1
      assert {:error, :unauthorized} = Volunteers.get_batch(Scope.for_user(user), batch.id)
      forbidden |> reload_page() |> refute_has("#volunteer-signups")
      new_device(c) |> visit("/volunteer-signups") |> refute_has("#volunteer-signups")
      finish(id)
    end

    test "VOL-05 provider failures, safe retry and recipient confirmation", c do
      id = "VOL-05"
      user = manager(c, [c.montreal])

      Application.put_env(:pauseai_ca, :volunteer_test_outcomes, %{
        "recover2@example.org" => :rejected,
        "recover3@example.org" => :unknown
      })

      b =
        open_workspace(c.conn, user, id)
        |> paste(3, "recover")
        |> review(3, id)
        |> confirm(id)
        |> assert_has("#batch-result", text: "Failed — retry available")
        |> assert_has("#batch-result", text: "Delivery unknown")
        |> capture(
          id,
          "Read accepted, rejected and ambiguous outcomes",
          "All three accounts exist; unknown delivery has no retry action"
        )

      invitation("recover1@example.org")
      assert Repo.aggregate(Signup, :count) == 3
      Application.put_env(:pauseai_ca, :volunteer_test_outcomes, %{})

      b =
        b
        |> reload_page()
        |> click_button("Retry invitation")
        |> assert_has("#batch-result", text: "Retry requested")

      message = invitation("recover2@example.org")

      new_device(c)
      |> show_email(message)
      |> capture(id, "Open the retried message", "Actual retry uses the same account")
      |> sign_in_email()

      b
      |> click_button("Refresh results")
      |> assert_has("#batch-result", text: "Email confirmed")
      |> capture(
        id,
        "Refresh after volunteer confirmation",
        "Accepted mail was not automatically resent; unknown stays blocked"
      )

      refute_receive {:email, %{to: [{"", "recover1@example.org"}]}}
      assert Repo.aggregate(Signup, :count) == 3

      admin =
        open_workspace(new_device(c), c.admin, id)
        |> click_link("Untitled batch · Confirmed")
        |> select("Verified provider outcome", option: "Failed")
        |> fill_in("Provider verification reference", with: "isolated-provider-check")
        |> click_button("Record reconciliation")
        |> capture(
          id,
          "Record a verified provider rejection",
          "Administrator reconciliation unlocks a safe retry"
        )

      b
      |> click_button("Refresh results")
      |> assert_has("#batch-result", text: "Failed — retry available")
      |> capture(
        id,
        "Refresh after verified provider reconciliation",
        "A definite failure can now be retried"
      )

      admin |> assert_has("#volunteer-signups")
      finish(id)
    end

    test "VOL-06 corrected draft, connection recovery and duplicate confirmation", c do
      id = "VOL-06"
      user = manager(c, [c.montreal])

      b =
        open_workspace(c.conn, user, id)
        |> paste(5, "draft")
        |> cell(1, "email", "invalid")
        |> assert_has("#signup-grid", text: "Enter a valid email")
        |> cell(1, "email", "draft1@example.org")
        |> click_button("Select eligible rows")
        |> fill_in("Source label", with: "Saved draft")
        |> click_button("Save draft")
        |> assert_has("body", text: "Draft saved")

      b =
        b
        |> fill_in("Search rows", with: "draft1")
        |> assert_has("#signup-grid tbody tr", count: 1)
        |> assert_has("#signup-selected", text: "5 selected")
        |> fill_in("Search rows", with: "")

      b =
        b
        |> evaluate("window.liveSocket.disconnect(); window.liveSocket.connect()")
        |> reload_page()
        |> assert_has("#signup-grid", text: "private-draft")
        |> assert_has("#signup-selected", text: "5 selected")
        |> capture(
          id,
          "Reconnect and reload a saved correction",
          "Rows, notes and selection survive without sending"
        )

      assert Repo.aggregate(Signup, :count) == 0
      b = review(b, 5, id)

      second =
        open_workspace(new_device(c), user, id)
        |> click_link("Saved draft · Draft")
        |> assert_has("#signup-review")

      b = confirm(b, id)

      second
      |> click_button("Create accounts and send invitations")
      |> assert_has("#batch-result")
      |> capture(
        id,
        "Confirm again from an older review",
        "The same batch result returns without duplicate effects"
      )

      for n <- 1..5, do: invitation("draft#{n}@example.org")
      assert Repo.aggregate(Invitation, :count) == 5

      b =
        b
        |> click_button("New batch")
        |> paste(1, "discard")
        |> fill_in("Source label", with: "Discard me")
        |> click_button("Save draft")
        |> assert_has("body", text: "Draft saved")

      discarded = Repo.get_by!(Batch, source: "Discard me")
      # Confirm browser dialog using the harness page event handler.
      b
      |> click_button("Discard draft")
      |> refute_has("nav a", text: "Discard me")
      |> capture(
        id,
        "Discard a separate unsent draft",
        "Discarded rows cannot be resumed and never create an account"
      )

      refute Repo.get(Batch, discarded.id)
      refute Accounts.get_user_by_email("discard1@example.org")
      finish(id)
    end

    test "VOL-07 ten immediate individual invitations and stable progress", c do
      id = "VOL-07"

      b =
        open_workspace(c.conn, c.admin, id)
        |> select("Default incubator / group", option: "Montréal")
        |> paste(10, "ten")
        |> review(10, id)
        |> confirm(id)

      for n <- 1..10, do: invitation("ten#{n}@example.org")

      b
      |> click_button("Refresh results")
      |> assert_has("#batch-result article", count: 10)
      |> reload_page()
      |> capture(
        id,
        "Refresh and reload ten results",
        "Ten accounts and ten separate invitation attempts, no outreach approval step"
      )

      batch = Repo.one!(Batch)
      assert {:ok, _} = Volunteers.confirm(c.scope, batch.id)
      assert Repo.aggregate(Signup, :count) == 10
      assert Repo.aggregate(Invitation, :count) == 10
      assert Enum.all?(Repo.all(Invitation), &(&1.status == "accepted"))
      finish(id)
    end

    test "VOL-10 Accounts contains single entry, search, editing and batch history within scope",
         c do
      id = "VOL-10"
      user = manager(c, [c.montreal])

      open_accounts(c.conn, user, id)
      |> refute_has("#managed-accounts", text: c.admin.email)
      |> click_link("Add account")
      |> assert_has("h1", text: "Add account")
      |> refute_has("#paste-rows")
      |> fill_in("Email", with: "single@example.org")
      |> fill_in("Name", with: "Single Exemple")
      |> fill_in("Postal code", with: "H2X1Y4")
      |> fill_in("Private organizer notes", with: "Private account note")
      |> click_button("Save draft")
      |> assert_has("body", text: "Draft saved")
      |> capture(
        id,
        "Save one account without sending",
        "Short form is durable and invitations have not started"
      )

      assert Repo.aggregate(Invitation, :count) == 0
      batch = Repo.one!(Batch)
      assert batch.entry_mode == "single"

      b =
        open_accounts(new_device(c), user, id)
        |> click_link("Untitled batch · Draft")
        |> refute_has("#paste-rows")
        |> assert_has("input[value='Single Exemple']")
        |> click_button("Review and invite")
        |> assert_has("#signup-review", text: "single@example.org")
        |> confirm(id)

      email = invitation("single@example.org")

      new_device(c)
      |> show_email(email)
      |> sign_in_email()
      |> refute_has("#account-management-links")

      account = Accounts.get_user_by_email("single@example.org")
      assert account.confirmed_at

      b =
        b
        |> click_link("Accounts")
        |> fill_in("Search accounts", with: "single@example.org")
        |> assert_has("#managed-accounts", text: "single@example.org")
        |> capture(
          id,
          "Find the created account",
          "Account directory reflects email confirmation"
        )
        |> click_link("single@example.org")
        |> assert_has("#managed-account-form", text: "Private organizer notes")
        |> fill_in("Name", with: "Updated Exemple")
        |> click_button("Save account")
        |> assert_has("body", text: "Account saved")
        |> assert_has("input[value='Updated Exemple']")
        |> capture(
          id,
          "Manage the existing account",
          "Explicit name correction and invitation history are visible"
        )

      assert Accounts.get_user_by_email("single@example.org").name == "Updated Exemple"
      assert Repo.aggregate(Invitation, :count) == 1
      assert Repo.get!(Signup, Repo.one!(Signup).id).notes == "Private account note"
      b |> click_link("View batch and invitation actions") |> assert_has("#batch-result")

      other = manager(c, [c.quebec], "othermanager@example.org")

      open_accounts(new_device(c), other, id)
      |> fill_in("Search accounts", with: "single@example.org")
      |> assert_has("body", text: "No accounts found")
      |> visit("/manage/accounts/#{account.id}")
      |> assert_has("body", text: "Account unavailable")
      |> refute_has("body", text: "Private account note")
      |> capture(
        id,
        "Deny another group's account URL",
        "The directory and detail view enforce the same scope"
      )

      open_accounts(new_device(c), c.admin, id)
      |> fill_in("Search accounts", with: "single@example.org")
      |> assert_has("#managed-accounts", text: "single@example.org")

      finish(id)
    end

    defp manager(c, groups, email \\ "manager@example.org") do
      user =
        user_fixture(%{email: email})
        |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
        |> Repo.update!()

      for group <- groups, do: Volunteers.assign_manager(c.scope, group.id, email)
      user
    end

    defp open_accounts(browser, user, id) do
      {token, _} = generate_user_magic_link_token(user)

      browser =
        browser
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_has("#account-menu")
        |> capture(id, "Sign in as the organizer", "Authenticated starting page")
        |> account_menu()
        |> refute_has("#account-menu", text: "Volunteer signups")
        |> refute_has("#management-menu")
        |> assert_has("#account-management-links", text: "Accounts")

      browser =
        if user.superadmin,
          do: assert_has(browser, "#account-management-links", text: "Admin dashboard"),
          else: refute_has(browser, "#account-management-links", text: "Admin dashboard")

      browser
      |> capture(
        id,
        "Open account menu",
        "Personal pages, account management, and session actions form separate groups"
      )
      |> click_link("Accounts")
      |> assert_has("#managed-accounts")
      |> capture(
        id,
        "Open Accounts",
        "Search accounts, add one or multiple, and resume saved batches"
      )
    end

    defp open_workspace(browser, user, id) do
      open_accounts(browser, user, id)
      |> click_link("Add multiple accounts")
      |> assert_has("#volunteer-signups")
      |> capture(
        id,
        "Open Add multiple accounts",
        "Editable rows are an account creation workflow"
      )
    end

    defp account_menu(b) do
      evaluate(
        b,
        "!!document.querySelector('#flash-info')?.getBoundingClientRect().height",
        &Process.put(:has_info, &1)
      )

      b = if Process.get(:has_info), do: click(b, "#flash-info button"), else: b
      click(b, "#account-menu summary")
    end

    defp new_device(c, width \\ 1280) do
      config =
        PhoenixTest.Playwright.Config.validate!(
          browser_context_opts: [viewport: %{width: width, height: 900}]
        )

      PhoenixTest.Playwright.Case.new_session(config, c)
    end

    defp fill_in(b, label, opts),
      do: b |> assert_has("[data-phx-main].phx-connected") |> PhoenixTest.fill_in(label, opts)

    defp select(b, label, opts),
      do: PhoenixTest.select(b, label, Keyword.put(opts, :exact, false))

    defp select(b, selector, label, opts),
      do: PhoenixTest.select(b, selector, label, Keyword.put(opts, :exact, false))

    defp cell(b, n, field, value) do
      label = %{"name" => "Name", "email" => "Email", "postal_code" => "Postal code"}[field]

      PhoenixTest.fill_in(
        b,
        "#signup-grid tbody tr:nth-child(#{n}) input[name$='[#{field}]']",
        label,
        with: value
      )
    end

    defp paste(b, count, prefix, group \\ "") do
      text =
        Enum.map_join(
          1..count,
          "\n",
          &"Person #{&1}\t#{prefix}#{&1}@example.org\tH2X 1Y4\t#{group}\tprivate-#{prefix}-#{&1}"
        )

      b
      |> fill_in("Paste spreadsheet rows", with: text)
      |> click_button("Add pasted rows")
      |> assert_has("#signup-grid tbody tr", count: min(count, 25))
    end

    defp review(b, count, id) do
      b
      |> click_button("Select eligible rows")
      |> click_button("Review and invite")
      |> assert_has("#signup-review", text: "#{count} selected volunteer")
      |> assert_has("#invitation-preview iframe[srcdoc*='Bienvenue']")
      |> capture(
        id,
        "Review selected accounts and the actual invitation preview",
        "Exact recipients and effective groups are visible before confirmation"
      )
    end

    defp confirm(b, id) do
      b
      |> click_button("Create accounts and send invitations")
      |> assert_has("#batch-result", text: "Accepted by email provider")
      |> capture(
        id,
        "Confirm account creation and immediate invitations",
        "Durable account and per-row provider outcomes"
      )
    end

    defp invitation(recipient) do
      assert_receive {:email,
                      %{
                        to: [{"", ^recipient}],
                        subject: "Welcome to PauseAI Canada · Bienvenue à PauseAI Canada"
                      } = email},
                     8_000

      assert email.from == {"PauseAI Canada", "campaigns@example.org"}
      assert email.cc == [] and email.bcc == []
      assert email.subject == "Welcome to PauseAI Canada · Bienvenue à PauseAI Canada"
      assert email.html_body =~ "volunteer signup sheet"
      assert email.text_body =~ "inscription bénévole"
      email
    end

    defp show_email(b, email) do
      [_, body] = Regex.run(~r{<body[^>]*>(.*)</body>}s, email.html_body)

      escape = fn value ->
        value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      end

      html =
        "<html lang='en'><meta charset='utf-8'><style>body{margin:0;background:#eee;font:16px system-ui}header,section{padding:24px}header{background:#222;color:white}section{max-width:850px;margin:auto;background:white}</style><header>Captured test inbox · Actual isolated transport</header><section id='delivered-email'><h1>#{escape.(email.subject)}</h1><p>From: #{escape.(inspect(email.from))}</p><p>To: #{escape.(inspect(email.to))}</p><p>Cc / Bcc: None</p>#{body}</section></html>"

      visit(b, "data:text/html;base64," <> Base.encode64(html))
    end

    defp sign_in_email(b),
      do:
        b
        |> click_link("Sign in")
        |> click_button("Confirm and stay logged in")
        |> assert_has("#account-menu")

    defp capture(b, id, trigger, outcome) do
      scenario = Enum.find(@scenarios, &(&1.id == id))
      step = Process.get({:step, id}, 0) + 1
      Process.put({:step, id}, step)
      filename = "#{id}-#{String.pad_leading(to_string(step), 2, "0")}.png"
      started = System.monotonic_time(:millisecond)

      metadata = %{
        "scenario_id" => id,
        "step" => to_string(step),
        "user" => "Organizer / volunteer",
        "click_target" => trigger,
        "external_systems" =>
          "Isolated Swoosh transport; local database; no Catalyse configured or called"
      }

      AcceptanceHarness.Evidence.record_pending_step(
        filename,
        scenario.title,
        trigger <> " → " <> outcome,
        metadata
      )

      b = AtddEvidence.capture_full_page(b, filename)
      evaluate(b, "location.href", &Process.put(:url, &1))

      AtddEvidence.record_step(
        filename,
        scenario.title,
        trigger <> " → " <> outcome,
        Map.merge(metadata, %{
          "duration_ms" => System.monotonic_time(:millisecond) - started,
          "current_url" => AtddEvidence.safe_url(Process.get(:url)),
          "language" => scenario.language,
          "device" => "Browser #{Process.get(:evidence_geometry)["width"]}px wide",
          "geometry" => Process.get(:evidence_geometry)
        })
      )

      b
    end

    defp finish(id) do
      scenario = Enum.find(@scenarios, &(&1.id == id))
      AtddEvidence.mark_scenario_success!(scenario)
      AcceptanceHarness.Evidence.record_current_scenario_runtime(scenario)
    end
  end
end
