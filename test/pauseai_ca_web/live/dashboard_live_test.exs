defmodule PauseAiCaWeb.DashboardLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias PauseAiCa.Engagement
  alias PauseAiCa.Engagement.Action
  alias PauseAiCa.Accounts

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
    refute Action.pending?(action)
    assert has_element?(view, "#actions article", "Discussed AI risk with someone")

    view
    |> element("#actions article button[phx-click=delete]")
    |> render_click()

    assert PauseAiCa.Engagement.list_actions(scope) == []
  end

  test "a recorded action changes the next step after a refresh", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view
    |> form("#action-form",
      action: %{action_type: "learned", happened_on: "2026-08-03"}
    )
    |> render_submit()

    assert has_element?(view, "#suggested-next-step", "Talk with one person")
    assert has_element?(view, "#ladder-step-1[data-current]", "You are here")
    assert [%Action{confirmed_at: %DateTime{}}] = Engagement.list_actions(scope)

    {:ok, refreshed_view, _html} = live(conn, ~p"/dashboard")
    assert has_element?(refreshed_view, "#suggested-next-step", "Talk with one person")
    refute has_element?(refreshed_view, "#pending-actions")
  end

  test "the empty journal points to the first ladder rung", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#engagement-ladder")
    assert has_element?(view, "#ladder-step-1", "Start here")
  end

  test "sends members to their profile for riding information", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#fsa-reminder a[href='/en/profile']", "Complete my profile")
  end

  test "shows saved reading and formats dates for people", %{conn: conn, user: user, scope: scope} do
    {:ok, user} = Accounts.save_resource(user, "risk")
    conn = log_in_user(conn, user)

    {:ok, _action} =
      Engagement.create_action(scope, %{
        "action_type" => "learned",
        "happened_on" => ~D[2026-08-04],
        "confirmed_at" => DateTime.utc_now(:second)
      })

    {:ok, view, html} = live(conn, ~p"/en/actions")
    assert has_element?(view, "#saved-resources", "Understand existential risk")
    assert html =~ "August 4, 2026"
    refute html =~ ">2026-08-04<"
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
      assert has_element?(view, "#pending-actions", "Did you complete these actions?")
      assert has_element?(view, "#confirm-#{pending.id}", "Yes, I did")
      refute render(view) =~ "Did you send it?"
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

  describe "logging what happened off the platform" do
    test "an organiser can record where and how many", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Choosing the type reveals the fields that make sense for it.
      html =
        view
        |> form("#action-form", action: %{action_type: "organized"})
        |> render_change()

      assert html =~ "Where?"
      assert html =~ "Roughly how many people came?"

      view
      |> form("#action-form",
        action: %{
          action_type: "organized",
          happened_on: "2026-08-01",
          location: "Concordia University, Montréal",
          quantity: "23"
        }
      )
      |> render_submit()

      assert [action] = Engagement.list_actions(scope)
      assert action.location == "Concordia University, Montréal"
      assert action.quantity == 23
    end

    test "flyering asks how many went out", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      html = view |> form("#action-form", action: %{action_type: "flyered"}) |> render_change()
      assert html =~ "Roughly how many did you hand out"

      view
      |> form("#action-form",
        action: %{
          action_type: "flyered",
          happened_on: "2026-08-01",
          location: "Rue Sainte-Catherine",
          quantity: "150"
        }
      )
      |> render_submit()

      assert [action] = Engagement.list_actions(scope)
      assert action.quantity == 150
    end

    test "a reader is not asked how many people attended", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      html = view |> form("#action-form", action: %{action_type: "learned"}) |> render_change()

      refute html =~ "Where?"
      refute html =~ "How many"
    end

    test "detail that stops applying is dropped rather than kept", %{scope: scope} do
      # Someone picks "organized", fills in a count, then switches to "learned".
      # The browser no longer shows the field; the server must not keep the value.
      {:ok, action} =
        Engagement.create_action(scope, %{
          "action_type" => "learned",
          "happened_on" => Date.utc_today(),
          "location" => "somewhere",
          "quantity" => "99"
        })

      assert is_nil(action.location)
      assert is_nil(action.quantity)
    end

    test "the record shows the place and the count", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Reveal the detail fields first; they do not exist until a type wants them.
      view |> form("#action-form", action: %{action_type: "event"}) |> render_change()

      html =
        view
        |> form("#action-form",
          action: %{
            action_type: "event",
            happened_on: "2026-08-01",
            location: "Montréal",
            quantity: "40"
          }
        )
        |> render_submit()

      assert html =~ "Montréal"
      assert html =~ "40"
    end

    test "joining and signing are offered as things to log", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Joined PauseAI"
      assert html =~ "Signed the PauseAI statement"
      assert html =~ "Handed out flyers"
    end
  end
end
