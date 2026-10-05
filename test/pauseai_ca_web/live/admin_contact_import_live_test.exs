defmodule PauseAiCaWeb.AdminContactImportLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures

  alias PauseAiCa.{ContactMigration, Repo}

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{admin: admin, conn: log_in_user(conn, admin)}
  end

  test "is restricted to superadmins" do
    member = user_fixture()
    conn = build_conn() |> log_in_user(member) |> get(~p"/admin/contact-imports")
    assert conn.status == 403
  end

  test "previews without persistence, preserves manual selection across search, and imports only selected rows",
       %{conn: conn} do
    existing = user_fixture(%{email: "ada@example.org"})
    {:ok, view, _html} = live(conn, ~p"/admin/contact-imports")

    csv =
      "email,name,city,status\nada@example.org,Ada Active,Montréal,known_active\nrené@example.org,René Review,Québec,\nbad-address,Bad Row,Toronto,\n"

    upload =
      file_input(view, "form[phx-submit='preview']", :contacts_csv, [
        %{name: "contacts.csv", content: csv, type: "text/csv"}
      ])

    render_upload(upload, "contacts.csv")

    view
    |> form("form[phx-submit='preview']", import: %{source: "legacy-sheet"})
    |> render_submit()

    assert has_element?(view, "#contact-preview", "3 rows found")
    assert ContactMigration.list_contacts() == []
    assert has_element?(view, "#preview-row-4 input[disabled]")

    view |> element("#preview-row-2 input") |> render_click()
    view |> form("form[phx-change='search-preview']", search: "Québec") |> render_change()
    assert has_element?(view, "#selected-count", "1 selected")
    view |> element("#preview-row-3 input") |> render_click()
    view |> form("#contact-selection-form") |> render_submit()

    assert render(view) =~ "Imported 2 contacts"
    assert [ada] = ContactMigration.list_contacts("ada@")
    assert ada.user_id == existing.id
    assert ContactMigration.list_contacts("bad-address") == []
  end

  test "fourteen selected protest contacts recover from an empty selection and import together",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/contact-imports")

    csv =
      "Name,Email,City,Source,Signup\n" <>
        Enum.map_join(
          1..14,
          "\n",
          &"Protester #{&1},protester-#{&1}@example.org,Montreal,Protest,2026-09-26"
        )

    upload =
      file_input(view, "form[phx-submit='preview']", :contacts_csv, [
        %{name: "protest.csv", content: csv, type: "text/csv"}
      ])

    render_upload(upload, "protest.csv")
    view |> form("form[phx-submit='preview']", import: %{source: "protest"}) |> render_submit()
    view |> form("#contact-selection-form") |> render_submit()
    assert render(view) =~ "Select at least one valid contact."
    view |> element("button[phx-click='select-visible']") |> render_click()
    assert has_element?(view, "#selected-count", "14 selected")
    refute render(view) =~ "Select at least one valid contact."
    view |> form("#contact-selection-form") |> render_submit()
    assert render(view) =~ "Imported 14 contacts"
    assert length(ContactMigration.list_contacts("protester-")) == 14
    assert Repo.aggregate(PauseAiCa.Accounts.User, :count) == 1
  end

  test "shows the responsible administrator in a contact timeline", %{conn: conn, admin: admin} do
    row = %{
      "email" => "history@example.org",
      "name" => "History",
      "city" => "",
      "source_key" => "",
      "status" => ""
    }

    assert {:ok, _} =
             ContactMigration.import_selected([row], "history.csv", "legacy-sheet", admin)

    [contact] = ContactMigration.list_contacts("history@")

    {:ok, view, _html} = live(conn, ~p"/admin/contact-imports")
    view |> element("#contact-#{contact.id} button", "View activity") |> render_click()

    assert has_element?(view, "#contact-#{contact.id} time")
    assert has_element?(view, "#contact-#{contact.id}", admin.email)
  end

  test "receipt search and page size survive reload and fresh revocation blocks import", %{
    conn: conn,
    admin: admin
  } do
    rows =
      for n <- 1..12,
          do: %{
            "email" => "receipt-#{n}@example.org",
            "name" => "Receipt #{n}",
            "city" => "Montréal"
          }

    {:ok, %{import: receipt}} =
      ContactMigration.import_selected(rows, "original.csv", "receipt-source", admin)

    {:ok, _} =
      ContactMigration.import_selected(
        [hd(rows), %{"email" => "other@example.org"}],
        "later.csv",
        "receipt-source",
        admin
      )

    uri = ~p"/admin/contact-imports?#{%{import: receipt.id, q: "receipt", page: 1, per: 10}}"
    {:ok, view, _} = live(conn, uri)
    assert has_element?(view, "#receipt-summary")
    assert has_element?(view, "#contact-pagination", "Page 1 of 2 · 12 contacts")
    refute has_element?(view, "#managed-contacts", "other@example.org")
    view |> element("#contact-pagination button", "Next") |> render_click()
    next_uri = ~p"/admin/contact-imports?#{%{q: "receipt", page: 2, per: 10, import: receipt.id}}"
    assert_patch(view, next_uri)
    {:ok, reloaded, _} = live(conn, next_uri)
    assert has_element?(reloaded, "#contact-pagination", "Page 2 of 2 · 12 contacts")
    assert has_element?(reloaded, "#receipt-select option[selected]", "original.csv")
    before = Repo.aggregate(PauseAiCa.ContactMigration.Import, :count)
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    reloaded |> form("#receipt-filter", import: "") |> render_change()
    assert_redirect(reloaded, ~p"/dashboard")
    assert Repo.aggregate(PauseAiCa.ContactMigration.Import, :count) == before
  end

  test "paginates large previews by 25 and keeps selection across pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/contact-imports")

    rows =
      Enum.map_join(1..30, "\n", fn number ->
        ",Contact #{number},contact-#{number}@example.org,Montréal,,,,Legacy,,,,,,,,,,"
      end)

    csv =
      "Status,Name,Email,City,Discord,Discord User ID,Signup Date,Source,Email Verified,Skills/Interests,Bio,Welcomed Date,Welcomed By,Notes,Processed At,Intro,Next Meetup,Meetups Attended\n" <>
        rows

    upload =
      file_input(view, "form[phx-submit='preview']", :contacts_csv, [
        %{name: "contacts.csv", content: csv, type: "text/csv"}
      ])

    render_upload(upload, "contacts.csv")

    view
    |> form("form[phx-submit='preview']", import: %{source: "legacy-sheet"})
    |> render_submit()

    assert has_element?(view, "#preview-pagination", "Page 1 of 2 · 30 contacts")
    view |> element("#preview-row-2 input") |> render_click()
    view |> element("#preview-pagination button", "Next") |> render_click()
    assert has_element?(view, "#preview-pagination", "Page 2 of 2 · 30 contacts")
    assert has_element?(view, "#selected-count", "1 selected")
    view |> form("#contact-selection-form") |> render_submit()
    assert render(view) =~ "Imported 1 contact"
    assert [contact] = ContactMigration.list_contacts("contact-")
    assert contact.email == "contact-1@example.org"
  end
end
