if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.ContactImportReplayTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{ContactMigration, CRM, Repo}
    alias PauseAiCa.Accounts.{Scope, User}
    alias PauseAiCa.ContactMigration.{Contact, Activity, Import}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenario %{
      id: "safe-repeatable-contact-migration",
      title: "PA-IMPORT-02 · Preserve corrections, withdrawals and source history on replay",
      tags: ["contacts", "accounts", "superadmin"],
      roles: ["Superadmin"],
      language: "English",
      device: "Desktop",
      source_file: __ENV__.file
    }

    test "PA-IMPORT-02 replay and receipt recovery preserve effects and deny other roles", c do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      AtddEvidence.reset!(@scenario.title, [@scenario], %{
        browser: "Chromium",
        viewport: "1280×900"
      })

      admin =
        user_fixture(%{email: "replay-admin@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      member = user_fixture(%{email: "replay-member@example.org"})
      scope = Scope.for_user(admin)
      flush_emails()

      before = %{
        users: Repo.aggregate(User, :count),
        invitations: Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count),
        memberships: Repo.aggregate(PauseAiCa.Volunteers.Signup, :count)
      }

      row = %{
        "email" => "replay-subject@example.org",
        "name" => "Source name",
        "city" => "Montréal",
        "source_key" => "tab:2",
        "status" => "needs_review",
        "signup_date" => "2025-12-28",
        "snapshot" => "snapshot-a",
        "row" => 2
      }

      {:ok, %{contacts: [original], import: receipt}} =
        ContactMigration.import_selected([row], "original.csv", "replay-sheet", admin)

      {:ok, record} = CRM.get_legacy(scope, original.id)
      # Reviewed scenario precondition: a human correction and a withdrawal already exist.
      {:ok, _} = CRM.update(scope, record, %{"name" => "Human correction", "city" => "Québec"})

      original
      |> Ecto.Changeset.change(
        name: "Human correction",
        city: "Québec",
        classification: "do_not_contact"
      )
      |> Repo.update!()

      b =
        sign_in(c.conn, admin)
        |> visit("/admin/contact-imports?import=#{receipt.id}&locale=en")
        |> assert_has("#receipt-summary")
        |> assert_has("#managed-contacts", text: "Do not contact")
        |> capture(
          "Open the original reviewed receipt",
          "Human correction and withdrawal exist before replay"
        )

      csv =
        "email,name,city,source_key,status,signup_date,snapshot\nreplay-subject@example.org,Changed source,Ottawa,tab:2,known_active,2026-01-01,snapshot-b\n"

      path = Path.join("tmp", "PA-IMPORT-02.csv")
      File.write!(path, csv)

      b =
        b
        |> upload("CSV file", path)
        |> fill_in("Source label", with: "replay-sheet")
        |> click_button("Preview")
        |> assert_has("#contact-preview", text: "Changed source")
        |> capture(
          "Preview a changed source observation",
          "Nothing has been imported during preview"
        )

      assert Repo.aggregate(Import, :count) == 1

      b =
        b
        |> check("Select replay-subject@example.org")
        |> click_button("Import selected contacts")
        |> assert_has("#managed-contacts", text: "Do not contact")
        |> capture(
          "Import the reviewed changed observation",
          "Withdrawal persists; a new receipt records the raw observation"
        )

      preserved = Repo.get!(Contact, original.id)
      assert preserved.name == "Human correction"
      assert preserved.city == "Québec"
      assert preserved.inserted_at == original.inserted_at
      assert Repo.aggregate(Contact, :count) == 1
      assert Repo.aggregate(PhoenixCRM.Person, :count) == 1
      assert {:ok, %{person: %{name: "Human correction"}}} = CRM.get(scope, record.person.id)

      b =
        b
        |> visit(
          "/admin/contact-imports?import=#{receipt.id}&locale=en&q=replay-subject&page=1&per=10"
        )
        |> assert_has("#receipt-summary")
        |> click_button("View activity")
        |> assert_has("#managed-contacts", text: "By replay-admin@example.org")

      b =
        PhoenixTest.Playwright.evaluate(
          b,
          "document.querySelectorAll('#managed-contacts details').forEach(x=>x.open=true)"
        )

      b =
        b
        |> assert_has("#managed-contacts", text: "snapshot-a")
        |> assert_has("#managed-contacts", text: "snapshot-b")
        |> capture(
          "Reopen the original receipt and source timeline",
          "Both raw observations and dates remain accessible with the importing actor"
        )

      assert Repo.aggregate(Activity, :count) == 2

      _b =
        b
        |> visit(
          "/admin/contact-imports?import=#{receipt.id}&locale=en&q=replay-subject&page=1&per=10"
        )
        |> assert_has("#contact-pagination", text: "1 contacts")
        |> capture(
          "Reload the receipt query",
          "Search and page size retain the original receipt membership"
        )

      denied =
        PhoenixTest.Playwright.Case.new_session(
          PhoenixTest.Playwright.Config.validate!(
            browser_context_opts: [viewport: %{width: 1280, height: 900}]
          ),
          c
        )
        |> sign_in(member)
        |> visit("/admin/contact-imports?import=#{receipt.id}&locale=en")
        |> refute_has("#admin-contact-imports")

      capture(
        denied,
        "Attempt the same receipt as a non-admin",
        "Private source history is denied without state changes"
      )

      assert {:error, :actor, :unauthorized, _} =
               ContactMigration.import_selected([row], "denied.csv", "replay-sheet", member)

      assert before == %{
               users: Repo.aggregate(User, :count),
               invitations: Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count),
               memberships: Repo.aggregate(PauseAiCa.Volunteers.Signup, :count)
             }

      assert Repo.aggregate(Import, :count) == 2
      refute_receive {:email, _}
      AtddEvidence.mark_scenario_success!(@scenario)
      AtddEvidence.finalize!()
    end

    defp sign_in(b, user) do
      {token, _} = generate_user_magic_link_token(user)

      b
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp flush_emails do
      receive do
        {:email, _} -> flush_emails()
      after
        0 -> :ok
      end
    end

    defp capture(b, trigger, outcome) do
      step = Process.get(:import_step, 0) + 1
      Process.put(:import_step, step)
      filename = "PA-IMPORT-02-#{String.pad_leading(to_string(step), 2, "0")}.png"
      b = AtddEvidence.capture_full_page(b, filename)

      AtddEvidence.record_step(filename, trigger, outcome, %{
        "scenario_id" => @scenario.id,
        "scenario" => @scenario.title,
        "step" => "#{step}/6",
        "click_target" => trigger,
        "page_html" => AtddEvidence.page_html(b),
        "external_systems" => "Synthetic DB only; no provider mutation or send"
      })

      b
    end
  end
end
