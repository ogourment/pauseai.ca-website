defmodule PauseAiCaWeb.CrmDirectoryLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{CRM, Repo, ContactMigration}
  alias PauseAiCa.Accounts.{User, Scope}

  test "source filtering pages complete canonical results and survives reload without changing data",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)

    rows =
      for n <- 1..26 do
        %{
          "email" => "directory-#{n}@example.org",
          "name" => "Directory #{String.pad_leading(to_string(n), 2, "0")}",
          "sheet" => "mtl",
          "source" => "Notion test",
          "source_notes" => "20% match"
        }
      end

    assert {:ok, %{contacts: contacts}} =
             ContactMigration.import_selected(rows, "synthetic.csv", "directory", admin)

    user_count = Repo.aggregate(User, :count)

    before_sources =
      Repo.all(ContactMigration.Contact) |> Enum.map(&{&1.id, &1.source_data, &1.classification})

    assert {:ok, %{total: 26, pages: 2, page: 2, records: [_]}} =
             CRM.directory_page(scope, %{"q" => "mtl", "region" => "Montréal", "page" => "99"})

    assert {:ok, %{total: 26}} = CRM.directory_page(scope, %{"q" => "20%"})
    assert {:ok, %{total: 0}} = CRM.directory_page(scope, %{"q" => "source_notes"})

    assert {:ok, %{per: 25, page: 1}} =
             CRM.directory_page(scope, %{"per" => "99999", "page" => "-1"})

    conn = log_in_user(conn, admin)

    {:ok, view, _} =
      live(conn, "/admin/contacts?locale=en&q=mtl&region=Montr%C3%A9al&page=2&per=25")

    assert has_element?(view, "#crm-pagination", "Page 2 of 2 · 26 contacts")
    assert has_element?(view, "#crm-search[value='mtl']")
    assert has_element?(view, "#crm-region option[selected]", "Montréal")
    assert has_element?(view, "#crm-directory li", "Directory 26")
    refute has_element?(view, "#crm-directory li", "Directory 01")
    assert has_element?(view, "#crm-import-contacts", "Import Contacts")
    refute has_element?(view, "#management-more a", "Contact imports")
    assert has_element?(view, "#management-tab-links a", "Donation pledges")
    assert has_element?(view, "#management-tab-links a", "Emails")

    view
    |> form("#crm-search-form", %{
      "search" => "Notion test",
      "region" => "Montréal",
      "per" => "10"
    })
    |> render_change()

    assert_patch(
      view,
      "/admin/contacts?locale=en&page=1&per=10&q=Notion+test&region=Montr%C3%A9al"
    )

    assert has_element?(view, "#crm-pagination", "Page 1 of 3 · 26 contacts")
    view |> element("#crm-pagination a", "Next") |> render_click()
    uri = assert_patch(view)
    {:ok, reloaded, _} = live(conn, uri)
    assert has_element?(reloaded, "#crm-pagination", "Page 2 of 3 · 26 contacts")
    assert has_element?(reloaded, "#crm-search[value='Notion test']")
    assert Repo.aggregate(User, :count) == user_count

    assert Repo.all(ContactMigration.Contact)
           |> Enum.map(&{&1.id, &1.source_data, &1.classification}) == before_sources

    assert length(contacts) == 26

    Repo.update!(Ecto.Changeset.change(admin, superadmin: false))
    assert {:error, :unauthorized} = CRM.directory_page(scope, %{})
    view |> form("#crm-search-form", %{"search" => "mtl"}) |> render_change()
    assert_redirect(view, "/dashboard")
  end

  test "region precedence and merged source matches count one person", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)

    rows = [
      %{"email" => "origin-a@example.org", "name" => "Origin", "sheet" => "mtl"},
      %{
        "email" => "origin-b@example.org",
        "name" => "Origin",
        "sheet" => "Rest of Canada",
        "region" => "Estrie",
        "region_source" => "self_reported"
      }
    ]

    {:ok, %{contacts: [a, b]}} =
      ContactMigration.import_selected(rows, "synthetic.csv", "origins", admin)

    {:ok, first} = CRM.get_legacy(scope, a.id)
    {:ok, second} = CRM.get_legacy(scope, b.id)
    {:ok, comparison} = CRM.compare(scope, first.person.id, second.person.id)
    {:ok, _} = CRM.merge(scope, comparison, %{"preferred_address_id" => hd(first.addresses).id})

    assert {:ok, %{total: 1, records: [record], regions: regions}} =
             CRM.directory_page(scope, %{"q" => "origin-b", "region" => "Estrie"})

    assert "Estrie" in regions
    assert length(record.addresses) == 2
    assert {:ok, %{total: 0}} = CRM.directory_page(scope, %{"region" => "ROCanada"})

    {:ok, view, _} =
      live(log_in_user(conn, admin), "/admin/contacts?locale=en&q=origin-b&region=Estrie")

    assert has_element?(view, "#directory-source-summary-#{a.id}", "Montréal")
    assert has_element?(view, "#directory-source-summary-#{b.id}", "Estrie")
    assert has_element?(view, "#crm-pagination", "1 contacts")
  end
end
