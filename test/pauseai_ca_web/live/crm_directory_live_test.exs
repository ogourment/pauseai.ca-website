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
    assert has_element?(view, "#crm-directory tbody tr", "Directory 26")
    refute has_element?(view, "#crm-directory tbody tr", "Directory 01")
    assert has_element?(view, "#crm-import-contacts", "Import Contacts")
    refute has_element?(view, "#management-more a", "Contact imports")
    assert has_element?(view, "#section-navigation a", "Donation pledges")
    assert has_element?(view, "#section-navigation a", "Emails")

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

  test "canonical selection includes addressless records, all matches and retained off-filter choices",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    people = for n <- 1..26, do: Repo.insert!(%PhoenixCRM.Person{name: "Collection #{n}"})
    other = Repo.insert!(%PhoenixCRM.Person{name: "Different record"})
    scope = Scope.for_user(admin)
    assert {:ok, ids} = CRM.directory_ids(scope, %{"q" => "Collection"})
    assert Enum.sort(ids) == Enum.sort(Enum.map(people, & &1.id))

    {:ok, view, _} =
      live(log_in_user(conn, admin), "/admin/contacts?locale=en&q=Collection&per=10")

    assert has_element?(view, "#crm-collection-select-page[type=checkbox]")
    view |> element("button[phx-click=select-all-matched]") |> render_click()
    assert has_element?(view, "#crm-selection-actions", "26 selected across pages")
    refute has_element?(view, "#crm-contact-#{hd(people).id} button[phx-click=invite-account]")
    view |> form("#crm-search-form", %{search: "Different record"}) |> render_change()
    assert has_element?(view, "#crm-selection-actions", "26 selected outside the current filters")
    assert has_element?(view, "#crm-contact-#{other.id}")
    render_click(view, "select-contact", %{"id" => hd(people).id})
    assert has_element?(view, "#crm-selection-actions", "26 selected across pages")
    view |> element("#crm-select-#{other.id}") |> render_click()
    assert has_element?(view, "#crm-selection-actions", "27 selected across pages")
    view |> element("button[phx-click=clear-selection]") |> render_click()
    assert has_element?(view, "#crm-selection-actions", "0 selected across pages")
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = CRM.directory_ids(scope, %{})
  end

  test "list membership removal uses server list context, preserves filters and retains global selection",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)

    people =
      for name <- ["Keep context one", "Second selected"],
          do: Repo.insert!(%PhoenixCRM.Person{name: name})

    ids = Enum.map(people, & &1.id)

    assert {:ok, list} =
             PauseAiCa.ContactLists.save(scope, nil, %{
               "name" => "Remove selection",
               "kind" => "static"
             })

    assert {:ok, list} = PauseAiCa.ContactLists.add_members(scope, list.id, ids, list.revision)

    assert {:ok, other} =
             PauseAiCa.ContactLists.save(scope, nil, %{
               "name" => "Untouched list",
               "kind" => "static"
             })

    assert {:ok, other} = PauseAiCa.ContactLists.add_members(scope, other.id, ids, other.revision)

    {:ok, view, _} =
      live(
        log_in_user(conn, admin),
        "/admin/contacts?locale=en&per=10&saved_filter_id=#{list.id}"
      )

    refute has_element?(view, "#crm-remove-from-list")
    view |> element("button[phx-click=select-page]") |> render_click()
    view |> form("#crm-search-form", %{search: "Keep context"}) |> render_change()

    query =
      view |> assert_patch() |> URI.parse() |> Map.fetch!(:query) |> Plug.Conn.Query.decode()

    assert query["saved_filter_id"] == list.id
    assert query["q"] == "Keep context"
    assert query["per"] == "10"
    assert has_element?(view, "#crm-selection-actions", "2 selected across pages")
    render_click(view, "collection-remove-from-list", %{"list_id" => other.id, "revision" => "0"})
    assert {:ok, changed} = PauseAiCa.ContactLists.get(scope, list.id)
    assert changed.criteria["person_ids"] == []
    assert {:ok, ^other} = PauseAiCa.ContactLists.get(scope, other.id)
    assert has_element?(view, "#crm-search[value='Keep context']")
    assert has_element?(view, "#crm-per option[value='10'][selected]")
    assert has_element?(view, "#crm-selection-actions", "2 selected across pages")
    assert has_element?(view, "#crm-selection-actions", "2 selected outside the current filters")
    refute has_element?(view, "#crm-contact-#{hd(people).id}")
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    render_click(view, "collection-remove-from-list", %{"list_id" => other.id})
    assert has_element?(view, "#crm-error")
    assert Repo.get!(PhoenixCRM.MailingList, list.id).revision == changed.revision
  end
end
