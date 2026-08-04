defmodule PauseAiCaWeb.ProfileLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias PauseAiCa.{Accounts, Repo}

  setup :register_and_log_in_user

  test "requires an authenticated user" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/en/profile")
  end

  test "stores a full postal code and shows the matched MP honestly", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/en/profile")

    view
    |> form("#profile-form", profile: %{postal_code: "h2x 1y4", local_updates: true})
    |> render_submit()

    assert has_element?(view, "#mp-result", "Steven Guilbeault")
    assert has_element?(view, "#mp-result", "Laurier—Sainte-Marie")
    assert has_element?(view, "#mp-position", "not yet documented")

    stored = Repo.get!(Accounts.User, user.id)
    assert stored.postal_code == "H2X1Y4"
    assert stored.fsa == "H2X"
    assert stored.local_updates
    assert stored.representative["name"] == "Steven Guilbeault"
  end

  test "manages saved nuggets and personal resource links", %{conn: conn, user: user} do
    {:ok, user} = Accounts.save_resource(user, "risk")
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/en/profile")

    assert has_element?(view, "#profile-saved-resources", "Understand existential risk")

    view
    |> form("#custom-resource-form", resource: %{url: "https://example.org/useful-reading"})
    |> render_submit()

    assert has_element?(view, "#custom-resources a[href='https://example.org/useful-reading']")

    stored = Repo.get!(Accounts.User, user.id)
    assert stored.custom_resource_urls == ["https://example.org/useful-reading"]

    view
    |> element("button[phx-click='remove-saved-resource'][phx-value-resource='risk']")
    |> render_click()

    refute has_element?(view, "#profile-saved-resources", "Understand existential risk")
  end
end
