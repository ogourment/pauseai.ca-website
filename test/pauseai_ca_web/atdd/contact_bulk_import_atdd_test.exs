if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.ContactBulkImportTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{ContactMigration, Repo}
    alias PauseAiCa.Accounts.User
    alias PauseAiCa.ContactMigration.{Contact, Import}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenario %{
      id: "human-checkbox-bulk-contact-import",
      title:
        "PA-IMPORT-03 · Select fourteen CSV contacts, recover validation and reload the receipt",
      tags: ["contacts", "accounts", "superadmin"],
      roles: ["Superadmin"],
      language: "English",
      device: "Desktop",
      source_file: __ENV__.file
    }

    test "PA-IMPORT-03 checkbox batch persists exactly once with readable dates and no outreach effects",
         c do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      AtddEvidence.reset!(@scenario.title, [@scenario], %{
        browser: "Chromium",
        viewport: "1280×900"
      })

      admin =
        user_fixture(%{email: "bulk-admin@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      existing = user_fixture(%{email: "bulk-1@example.org"})
      original_req_options = Application.fetch_env!(:pauseai_ca, :brevo_req_options)
      test_pid = self()

      Application.put_env(:pauseai_ca, :brevo_req_options,
        plug: fn conn ->
          send(test_pid, {:bulk_provider_request, conn.method, conn.request_path})
          PauseAiCa.BrevoStub.call(conn)
        end
      )

      on_exit(fn ->
        Application.put_env(:pauseai_ca, :brevo_req_options, original_req_options)
      end)

      baseline = side_effect_counts()
      flush_emails()

      csv =
        "Name,Email,City,Source,Signup\n" <>
          Enum.map_join(
            1..14,
            "\n",
            &"Synthetic protester #{&1},bulk-#{&1}@example.org,Montreal,Protest,45945"
          )

      path = Path.join("tmp", "PA-IMPORT-03.csv")
      File.write!(path, csv)
      {token, _} = generate_user_magic_link_token(admin)

      b =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/admin/contact-imports?locale=en")
        |> upload("CSV file", path)
        |> fill_in("Source label", with: "synthetic-protest")
        |> click_button("Preview")
        |> assert_has("#contact-preview", text: "14 rows found")
        |> assert_has("#preview-source-summary-2", text: "2025-10-15")
        |> capture(
          "Preview fourteen contacts",
          "Spreadsheet dates are readable; preview writes nothing"
        )

      assert Repo.aggregate(Contact, :count) == 0
      assert Repo.aggregate(Import, :count) == 0

      b =
        b
        |> click_button("Import selected contacts")
        |> assert_has("#selection-error", text: "Select at least one valid contact.")
        |> capture(
          "Try import before selecting",
          "Validation is recoverable beside the action; no persistence"
        )

      assert Repo.aggregate(Contact, :count) == 0

      b =
        Enum.reduce(1..14, b, fn n, browser -> check(browser, "Select bulk-#{n}@example.org") end)
        |> assert_has("#selected-count", text: "14 selected")
        |> refute_has("#selection-error")
        |> capture(
          "Check all fourteen rows individually",
          "Visible selection and submitted checkboxes agree; old validation is gone"
        )

      b =
        b
        |> click_button("Import selected contacts")
        |> assert_has("#flash-info", text: "Imported 14 contacts")
        |> assert_has("#receipt-summary")
        |> assert_has("#contact-pagination", text: "14 contacts")
        |> capture(
          "Import the checked batch",
          "Fourteen contacts and identities exist with an attributed receipt"
        )

      assert Repo.aggregate(Contact, :count) == 14
      assert Repo.aggregate(PhoenixCRM.Person, :count) == 14
      assert Repo.aggregate(Import, :count) == 1
      [linked] = ContactMigration.list_contacts("bulk-1@")
      assert linked.user_id == existing.id
      originals = Repo.all(Contact) |> Map.new(&{&1.id, {&1.inserted_at, &1.source_data}})
      assert Enum.all?(originals, fn {_, {_, data}} -> data["signup"] == "45945" end)
      receipt = Repo.one!(Import)

      b =
        b
        |> visit("/admin/contact-imports?import=#{receipt.id}&locale=en&page=1&per=10&q=bulk-")
        |> assert_has("#contact-pagination", text: "Page 1 of 2 · 14 contacts")
        |> click_button("Next")
        |> assert_has("#contact-pagination", text: "Page 2 of 2 · 14 contacts")
        |> capture(
          "Reload the receipt and open its next page",
          "Receipt query retains all fourteen imported contacts"
        )

      b =
        b
        |> upload("CSV file", path)
        |> fill_in("Source label", with: "synthetic-protest")
        |> click_button("Preview")
        |> click_button("Select visible valid contacts")
        |> assert_has("#selected-count", text: "14 selected")
        |> click_button("Import selected contacts")
        |> assert_has("#flash-info", text: "Imported 14 contacts")
        |> capture(
          "Repeat using select-visible",
          "The same fourteen contacts remain; a second receipt records the reviewed replay"
        )

      assert Repo.aggregate(Contact, :count) == 14
      assert Repo.aggregate(PhoenixCRM.Person, :count) == 14
      assert Repo.aggregate(Import, :count) == 2
      assert originals == Repo.all(Contact) |> Map.new(&{&1.id, {&1.inserted_at, &1.source_data}})
      assert baseline == side_effect_counts()
      refute_receive {:email, _}
      refute_receive {:bulk_provider_request, _, _}
      AtddEvidence.mark_scenario_success!(@scenario)
      AtddEvidence.finalize!()
      _ = b
    end

    defp side_effect_counts do
      %{
        users: Repo.aggregate(User, :count),
        invitations: Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count),
        memberships: Repo.aggregate(PauseAiCa.Volunteers.Signup, :count),
        mail_batches: Repo.aggregate(PauseAiCa.Mail.Batch, :count),
        mail_drafts: Repo.aggregate(PauseAiCa.Mail.Draft, :count)
      }
    end

    defp flush_emails do
      receive do
        {:email, _} -> flush_emails()
      after
        0 -> :ok
      end
    end

    defp capture(b, trigger, outcome) do
      step = Process.get(:bulk_import_step, 0) + 1
      Process.put(:bulk_import_step, step)
      filename = "PA-IMPORT-03-#{String.pad_leading(to_string(step), 2, "0")}.png"
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
