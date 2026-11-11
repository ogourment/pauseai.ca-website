defmodule PauseAiCaWeb.DataGridLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, CRM, ContactLists}
  alias PauseAiCa.Accounts.Scope

  setup do
    previous = Application.get_env(:pauseai_ca, :data_grid_enabled)
    Application.put_env(:pauseai_ca, :data_grid_enabled, true)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:pauseai_ca, :data_grid_enabled),
        else: Application.put_env(:pauseai_ca, :data_grid_enabled, previous)
    end)

    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{admin: admin, scope: Scope.for_user(admin)}
  end

  test "contacts filter and sort before bounded paging, preserve canonical selection and reuse email actions",
       %{conn: conn, admin: admin, scope: scope} do
    people =
      for n <- 1..28 do
        assert {:ok, record} =
                 CRM.create(scope, %{
                   "name" => "Grid #{String.pad_leading(to_string(n), 2, "0")}",
                   "email" => "grid-#{n}@example.org",
                   "city" => if(n <= 26, do: "Toronto", else: "Ottawa")
                 })

        record.person
      end

    {:ok, view, _} = live(log_in_user(conn, admin), "/admin/contacts?locale=en")
    assert has_element?(view, "#crm-grid[phx-hook='PhoenixDataGrid']")
    refute has_element?(view, "#crm-geography-options[open]")
    render_hook(view, "assistant-guided-observe", %{"token" => "synthetic-observation"})
    assert has_element?(view, "#crm-geography-options[open]")

    payload = %{
      "id" => "crm-grid",
      "request_id" => "page-2",
      "page_size" => 10,
      "page" => 2,
      "filters" => [%{"field" => "city", "operator" => "contains", "value" => "Toronto"}],
      "sort" => [%{"field" => "name", "direction" => "desc"}]
    }

    render_hook(view, "data_grid:query", payload)

    assert_push_event(view, "data_grid:rows", %{
      id: "crm-grid",
      request_id: "page-2",
      total: 26,
      rows: rows
    })

    assert length(rows) == 10
    assert hd(rows)["name"] == "Grid 16"
    assert List.last(rows)["name"] == "Grid 07"
    view |> element("button[phx-click='select-all-matched']") |> render_click()
    assert has_element?(view, "#crm-selection-actions", "26 selected across pages")
    view |> element("button[phx-click='clear-selection']") |> render_click()
    selected = hd(people).id
    render_hook(view, "data_grid:selection", %{"id" => "crm-grid", "ids" => [selected]})
    assert has_element?(view, "#crm-selection-actions", "1 selected across pages")
    view |> element("#crm-email-selected") |> render_click()
    {path, _} = assert_redirect(view)
    assert String.starts_with?(path, "/manage/mail/drafts/")
  end

  test "query validation and role revocation do not expose rows", %{conn: conn, admin: admin} do
    {:ok, view, _} = live(log_in_user(conn, admin), "/admin/contacts?locale=en")

    render_hook(view, "data_grid:query", %{
      "id" => "crm-grid",
      "request_id" => "invalid",
      "page_size" => 101
    })

    assert_push_event(view, "data_grid:rows", %{request_id: "invalid", error: true})
    Repo.update!(Ecto.Changeset.change(admin, superadmin: false))
    render_hook(view, "data_grid:query", %{"id" => "crm-grid", "request_id" => "revoked"})
    assert_redirect(view, "/dashboard")
  end

  test "lists use typed filters and fresh selection, opening the existing editor", %{
    conn: conn,
    admin: admin,
    scope: scope
  } do
    assert {:ok, list} =
             ContactLists.save(scope, nil, %{
               "name" => "Vancouver grid",
               "kind" => "dynamic",
               "city" => "Vancouver"
             })

    {:ok, view, _} = live(log_in_user(conn, admin), "/manage/lists?locale=fr")
    assert has_element?(view, "#lists-grid")

    render_hook(view, "data_grid:query", %{
      "id" => "lists-grid",
      "request_id" => "lists",
      "filters" => [%{"field" => "name", "operator" => "contains", "value" => "Vancouver"}]
    })

    assert_push_event(view, "data_grid:rows", %{total: 1, rows: [%{"id" => id}]})
    assert id == list.id
    render_hook(view, "data_grid:selection", %{"id" => "lists-grid", "ids" => [id]})
    render_hook(view, "data_grid:open_row", %{"id" => "lists-grid", "row_id" => id})
    assert_patch(view, "/manage/lists?locale=fr&list_id=#{id}")
    assert has_element?(view, "#selected-contact-list", "Vancouver grid")

    render_hook(view, "data_grid:query", %{
      "id" => "lists-grid",
      "request_id" => "bad",
      "filters" => %{"bad" => true}
    })

    assert_push_event(view, "data_grid:rows", %{request_id: "bad", error: true})
  end
end
