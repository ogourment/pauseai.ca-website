defmodule PauseAiCaWeb.AdminContactsHistoryLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{ContactMigration, Repo}

  test "shows original evidence with its precision without backdating migration or creating accounts",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    accounts_before = Repo.aggregate(PauseAiCa.Accounts.User, :count)

    history = %{
      "signup_date" => %{"value" => "2025-12-28", "precision" => "date"},
      "events" => [
        %{
          "kind" => "source_created",
          "value" => "2025-12-29T20:09:06.889Z",
          "precision" => "datetime",
          "timezone" => "UTC",
          "source" => "notion",
          "source_record_id" => "synthetic-record"
        },
        %{
          "kind" => "first_known_processing",
          "value" => "2026-03-24 13:11",
          "precision" => "datetime",
          "timezone" => "unknown",
          "source" => "pauseai_automations"
        }
      ]
    }

    row = %{
      "email" => "history@example.org",
      "name" => "Historical contact",
      "historical_dates" => Jason.encode!(history)
    }

    assert {:ok, %{contacts: [contact]}} =
             ContactMigration.import_selected([row], "synthetic.csv", "test-history", admin)

    {:ok, view, _} =
      live(log_in_user(conn, admin), ~p"/admin/contacts/legacy/#{contact.id}?locale=en")

    assert has_element?(view, "#crm-historical-dates time[datetime='2025-12-29T20:09:06.889Z']")
    assert has_element?(view, "#crm-historical-dates", "Original source record created")
    assert has_element?(view, "#crm-historical-dates time", "2025-12-29 20:09:06.889 UTC")
    assert has_element?(view, "#crm-historical-dates", "Date only; time unknown")
    assert has_element?(view, "#crm-historical-dates", "Timezone unknown")
    assert has_element?(view, "#crm-historical-dates", "synthetic-record")
    assert Repo.aggregate(PauseAiCa.Accounts.User, :count) == accounts_before

    assert Enum.all?(
             ContactMigration.list_activities(contact.id),
             &(DateTime.to_date(&1.inserted_at) == Date.utc_today())
           )

    refute has_element?(view, "#crm-activity time[datetime='2025-12-29T20:09:06.889Z']")
  end

  test "old or malformed date metadata remains readable" do
    alias PauseAiCa.ContactMigration.HistoricalDates
    assert HistoricalDates.entries(%{}) == []
    assert HistoricalDates.entries(%{"historical_dates" => "broken json"}) == []

    assert HistoricalDates.display_value(%{
             "value" => "2026-03-24 13:11",
             "precision" => "datetime",
             "timezone" => "unknown"
           }) == "2026-03-24 13:11"

    assert HistoricalDates.entries(%{
             "historical_dates" => %{"events" => [nil, %{"kind" => "invented"}]}
           }) == []
  end

  test "main directory and profile expose source metadata without opening details", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    accounts_before = Repo.aggregate(PauseAiCa.Accounts.User, :count)

    row = %{
      "email" => "summary@example.org",
      "name" => "Source summary",
      "source_notes" => "Preserved source note",
      "signup_date" => "2025-12-28",
      "sheet" => "Rest of Canada",
      "source" => "Notion ROC",
      "source_status" => "onboarded",
      "status" => "needs_review",
      "welcomed_date" => "2025-12-28"
    }

    assert {:ok, %{contacts: [contact]}} =
             ContactMigration.import_selected([row], "summary.csv", "summary", admin)

    conn = log_in_user(conn, admin)
    {:ok, directory, _} = live(conn, ~p"/admin/contacts?locale=en&q=summary")
    selector = "#directory-source-summary-#{contact.id}"

    for value <- [
          "Signup date",
          "2025-12-28",
          "Geography",
          "ROCanada",
          "Notion ROC",
          "Rest of Canada",
          "Source status",
          "onboarded",
          "Sheet status",
          "needs_review",
          "Welcomed date"
        ] do
      assert has_element?(directory, selector, value)
    end

    assert has_element?(
             directory,
             "#directory-source-details-#{contact.id} summary",
             "Show imported source fields"
           )

    assert has_element?(
             directory,
             "#directory-source-details-#{contact.id} dd",
             "Preserved source note"
           )

    refute has_element?(directory, "#directory-source-details-#{contact.id}[open]")
    {:ok, imported, _} = live(conn, ~p"/admin/contact-imports?locale=en&q=summary")

    assert has_element?(
             imported,
             "#imported-source-details-#{contact.id} dd",
             "Preserved source note"
           )

    {:ok, profile, _} = live(conn, ~p"/admin/contacts/legacy/#{contact.id}?locale=en")
    assert has_element?(profile, "#profile-source-summary-#{contact.id}", "ROCanada")
    assert has_element?(profile, "#profile-source-summary-#{contact.id}", "2025-12-28")

    assert has_element?(
             profile,
             "#crm-source-details details summary",
             "Show imported source fields"
           )

    assert has_element?(
             profile,
             "#profile-source-details-#{contact.id} dd",
             "Preserved source note"
           )

    refute has_element?(profile, "#crm-source-details details[open]")
    assert Repo.get!(ContactMigration.Contact, contact.id).source_data == row
    assert Repo.aggregate(PauseAiCa.Accounts.User, :count) == accounts_before
    assert Enum.map(ContactMigration.list_activities(contact.id), & &1.action) == ["imported"]
  end

  test "directory keeps both reconciled origins and rechecks current authorization" do
    alias PauseAiCa.{CRM, Accounts.Scope}
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)

    rows = [
      %{
        "email" => "origin-mtl@example.org",
        "name" => "Same person",
        "sheet" => "mtl",
        "signup_date" => "2025-11-13"
      },
      %{
        "email" => "origin-roqc@example.org",
        "name" => "Same person",
        "sheet" => "quebec",
        "signup_date" => "2025-10-15"
      }
    ]

    assert {:ok, %{contacts: contacts}} =
             ContactMigration.import_selected(rows, "origins.csv", "origins", admin)

    before = Enum.map(contacts, &{&1.id, &1.source_data}) |> Map.new()
    {:ok, [a, b]} = CRM.search(scope, "origin-")
    {:ok, comparison} = CRM.compare(scope, a.person.id, b.person.id)

    assert {:ok, _} =
             CRM.merge(scope, comparison, %{
               "preferred_address_id" => a.person.preferred_address_id
             })

    {:ok, records} = CRM.search(scope, "origin-")
    assert length(records) == 1
    assert {:ok, origins} = CRM.directory_origins(scope, records)
    assert Map.new(Map.fetch!(origins, hd(records).person.id), &{&1.id, &1.source_data}) == before
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert CRM.directory_origins(scope, records) == {:error, :unauthorized}
  end
end
