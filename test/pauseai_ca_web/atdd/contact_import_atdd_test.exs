if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.ContactImportTest do
    use AcceptanceHarness.Playwright.Case, async: false

    import PauseAiCa.AccountsFixtures

    alias AcceptanceHarness.Evidence
    alias PauseAiCa.Repo
    alias PauseAiCaWeb.AtddEvidence

    @moduletag :atdd

    @migration %{
      id: "safe-first-contact-migration",
      title: "A superadmin safely migrates a reviewed first batch of contacts",
      roles: ["Superadmin"],
      language: "English",
      device: "Desktop",
      source_file: __ENV__.file
    }

    @future [
      %{
        id: "review-to-incubator-invitation",
        title: "A reviewed contact becomes an invited incubator participant",
        steps: [
          {"cm-03", "Record a human review decision",
           "The superadmin records why the contact is eligible or needs further review."},
          {"cm-05", "Choose account activation separately",
           "Creating or activating a PauseAI.ca account remains distinct from an incubator invitation."},
          {"cm-14", "Apply a relationship action to the selection",
           "The superadmin chooses an incubator or event invitation for one or more reviewed contacts."},
          {"cm-15", "Accept the invitation",
           "Incubator membership exists only after the invited person accepts."}
        ]
      },
      %{
        id: "safe-repeatable-contact-migration",
        title: "A superadmin resumes migration without duplicating or reviving contacts",
        steps: [
          {"cm-06", "Reimport a stable source record",
           "A repeated source identity updates its existing contact instead of creating a duplicate."},
          {"cm-07", "Preserve a suppression decision",
           "A deleted or opted-out person is not restored by legacy data."},
          {"cm-09", "Resume an incremental batch",
           "The superadmin can search prior batches and reconcile what remains."}
        ]
      },
      %{
        id: "approved-contact-outreach",
        title: "A superadmin sends approved outreach and follows delivery",
        steps: [
          {"cm-11", "Edit and preview the message",
           "The selected CMS content is editable and previewable before any delivery request."},
          {"cm-12", "Approve the bounded recipient selection",
           "Only the contacts explicitly selected by the superadmin are handed to Brevo."},
          {"cm-13", "Follow delivery on each contact",
           "Brevo delivery states appear in the administrator-attributed contact timeline."}
        ]
      }
    ]

    @scenarios [@migration] ++
                 Enum.map(@future, fn scenario ->
                   Map.merge(scenario, %{
                     status: :ignored,
                     reason: "Accepted for a later Milestone 1 increment",
                     roles: ["Superadmin"],
                     language: "English",
                     device: "Desktop",
                     source_file: __ENV__.file
                   })
                 end)

    test "a superadmin safely migrates a reviewed first batch of contacts", %{conn: conn} do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      AtddEvidence.reset!("PauseAI Canada contact migration acceptance evidence", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop"
      })

      admin =
        user_fixture(%{email: "admin-import@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      _existing = user_fixture(%{email: "active-import@example.org"})
      {login_token, _token} = generate_user_magic_link_token(admin)

      browser =
        conn
        |> visit("/users/log-in/#{login_token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/admin/dashboard")
        |> click_link("Contact imports")
        |> assert_path("/admin/contact-imports")
        |> capture(
          "contact-import-01-workspace.png",
          "1/5",
          "Open the protected migration workspace",
          "The superadmin reaches the dedicated import area from a known signed-in state."
        )

      browser =
        browser
        |> upload("CSV file", "test/fixtures/contact_import_review.csv")
        |> fill_in("Source label", with: "legacy-sheet")
        |> click_button("Preview")
        |> assert_has("#contact-preview", text: "3 rows found")
        |> open_first_source_fields()
        |> assert_has("#contact-preview", text: "Meetups attended")
        |> assert_has("#contact-preview", text: "Facilitation")
        |> assert_has("#managed-contacts", text: "No imported contacts")
        |> assert_has("#preview-row-4", text: "Invalid email")
        |> capture(
          "contact-import-02-preview.png",
          "2/5",
          "Preview before persistence",
          "The file is staged for human review; invalid rows cannot be selected and no contact has been imported."
        )

      browser =
        browser
        |> check("Select active-import@example.org")
        |> fill_in("Search preview", with: "Québec")
        |> assert_has("#selected-count", text: "1 selected")
        |> check("Select review-import@example.org")
        |> capture(
          "contact-import-03-selection.png",
          "3/5",
          "Build the reviewed selection",
          "Manual checkbox selection survives a search change and has no arbitrary batch-size cap."
        )

      browser =
        browser
        |> click_button("Import selected contacts")
        |> assert_has("#managed-contacts", text: "active-import@example.org")
        |> assert_has("#managed-contacts", text: "Account matched")
        |> assert_has("#managed-contacts", text: "review-import@example.org")
        |> capture(
          "contact-import-04-reconciled.png",
          "4/5",
          "Import and reconcile the approved contacts",
          "Only the reviewed selection is persisted, and the matching PauseAI.ca account is identified."
        )

      _browser =
        browser
        |> fill_in("Search imported contacts", with: "active-import@example.org")
        |> within("#managed-contacts li:first-child", fn contact ->
          click_button(contact, "View activity")
        end)
        |> assert_has("#managed-contacts", text: "By admin-import@example.org")
        |> capture(
          "contact-import-05-timeline.png",
          "5/5",
          "Verify the accountable result",
          "The resulting contact timeline identifies which administrator performed the import and when."
        )

      Evidence.record_current_scenario_runtime(@migration)
      AtddEvidence.mark_scenario_success!(@migration)

      Enum.each(@future, &record_future_flow/1)
      AtddEvidence.finalize!()
    end

    defp record_future_flow(flow) do
      scenario = Enum.find(@scenarios, &(&1.id == flow.id))
      total = length(flow.steps)

      AcceptanceHarness.ignore(scenario, fn ->
        flow.steps
        |> Enum.with_index(1)
        |> Enum.each(fn {{step_id, title, description}, index} ->
          Evidence.record_pending_step("#{step_id}-pending.png", title, description, %{
            "scenario_id" => flow.id,
            "scenario" => flow.title,
            "step" => "#{index}/#{total}"
          })
        end)

        raise "not implemented in this increment"
      end)
    end

    defp open_first_source_fields(conn) do
      PhoenixTest.Playwright.evaluate(
        conn,
        "document.querySelector('#contact-preview details').open = true"
      )

      conn
    end

    defp capture(conn, filename, step, title, description) do
      started_at = System.monotonic_time(:millisecond)
      conn = AtddEvidence.capture_full_page(conn, filename)
      duration_ms = System.monotonic_time(:millisecond) - started_at
      page_html = AtddEvidence.page_html(conn)
      html_filename = Path.rootname(filename) <> ".html"
      html_path = Path.join(["tmp", "atdd", "html", html_filename])
      File.mkdir_p!(Path.dirname(html_path))
      File.write!(html_path, page_html)

      AtddEvidence.record_step(filename, title, description, %{
        "scenario_id" => @migration.id,
        "scenario" => @migration.title,
        "step" => step,
        "language" => @migration.language,
        "device" => @migration.device,
        "user" => hd(@migration.roles),
        "duration_ms" => duration_ms,
        "page_html" => page_html,
        "artifacts" => [%{"type" => "html", "path" => Path.join("html", html_filename)}]
      })

      conn
    end
  end
end
