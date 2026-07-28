defmodule PauseAiCaWeb.DashboardLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "records and deletes a private action", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#action-form")

    view
    |> form("#action-form",
      action: %{
        action_type: "conversation",
        happened_on: "2026-07-28",
        notes: "Talked with a neighbour"
      }
    )
    |> render_submit()

    [action] = PauseAiCa.Engagement.list_actions(scope)
    assert action.action_type == "conversation"
    assert has_element?(view, "#actions article", "Discussed AI risk with someone")

    view
    |> element("#actions article button[phx-click=delete]")
    |> render_click()

    assert PauseAiCa.Engagement.list_actions(scope) == []
  end

  test "requires an authenticated user", %{conn: _authenticated_conn} do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
  end
end
