defmodule PauseAiCaWeb.DashboardLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias PauseAiCa.Engagement
  alias PauseAiCa.Engagement.Action

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

  describe "actions we cannot vouch for" do
    setup %{scope: scope} do
      {:ok, pending} =
        Engagement.create_action(scope, %{
          "action_type" => "contacted_representative",
          "happened_on" => Date.utc_today(),
          "confirmed_at" => nil
        })

      %{pending: pending}
    end

    test "the dashboard asks rather than assuming", %{conn: conn, pending: pending} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#pending-actions")
      assert has_element?(view, "#pending-#{pending.id}")
    end

    test "confirming moves it into the record", %{conn: conn, scope: scope, pending: pending} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("#confirm-#{pending.id}") |> render_click()

      refute has_element?(view, "#pending-#{pending.id}")
      assert Engagement.list_pending_actions(scope) == []
      refute scope |> Engagement.list_actions() |> hd() |> Action.pending?()
    end

    test "declining removes it entirely", %{conn: conn, scope: scope, pending: pending} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("#discard-#{pending.id}") |> render_click()

      refute has_element?(view, "#pending-#{pending.id}")
      assert Engagement.list_actions(scope) == []
    end

    test "an unconfirmed action is not counted as done", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "0 actions recorded"
    end
  end
end
