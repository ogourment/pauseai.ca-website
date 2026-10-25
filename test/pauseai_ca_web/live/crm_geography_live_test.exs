defmodule PauseAiCaWeb.CRMGeographyLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{CRM, Repo}
  alias PauseAiCa.Accounts.Scope

  test "geography facet values survive pagination and reload and display canonical location", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)

    for n <- 1..11,
        do:
          CRM.create(scope, %{email: "city-#{n}@example.org", name: "City #{n}", city: "Toronto"})

    {:ok, outside} =
      CRM.create(scope, %{email: "outside@example.org", name: "Outside", city: "Vancouver"})

    conn = log_in_user(conn, admin)

    {:ok, view, _} =
      live(conn, "/admin/contacts?locale=en&provinces[]=ON&cities[]=Toronto&per=10")

    assert has_element?(view, "#crm-pagination", "11 contacts")
    assert has_element?(view, "#crm-provinces option[selected]", "Ontario")
    assert has_element?(view, "#crm-cities option[selected]", "Toronto")
    refute has_element?(view, "#crm-contact-#{outside.person.id}")
    assert has_element?(view, "[data-geography-version='canada-crm-v2']", "Ontario")
    assert has_element?(view, "label[for='crm-fsas']", "first three postal-code characters")
    view |> element("#crm-pagination a", "Next") |> render_click()
    path = assert_patch(view)
    query = path |> URI.parse() |> Map.fetch!(:query) |> Plug.Conn.Query.decode()
    assert query["provinces"] == ["ON"] and query["cities"] == ["Toronto"]
    {:ok, reloaded, _} = live(conn, path)
    assert has_element?(reloaded, "#crm-pagination", "Page 2 of 2 · 11 contacts")
    assert has_element?(reloaded, "#crm-provinces option[selected]", "Ontario")
    view |> element("button", "Select this page") |> render_click()
    assert has_element?(view, "#crm-selection-actions", "1 selected across pages")

    view
    |> form("#crm-search-form", %{
      "provinces" => ["BC"],
      "cities" => [],
      "region" => "",
      "fsas" => "",
      "unknown" => "false"
    })
    |> render_change()

    assert has_element?(view, "#crm-selection-actions", "0 selected across pages")
    assert has_element?(view, "#crm-contact-#{outside.person.id}")
  end
end
