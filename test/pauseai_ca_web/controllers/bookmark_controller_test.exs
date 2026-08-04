defmodule PauseAiCaWeb.BookmarkControllerTest do
  use PauseAiCaWeb.ConnCase

  alias PauseAiCa.Accounts

  setup :register_and_log_in_user

  test "a logged-in reader saves a resource to their account", %{conn: conn, user: user} do
    conn = post(conn, ~p"/bookmarks/risk?locale=fr")

    assert redirected_to(conn) == "/fr#resource-risk"
    assert Accounts.get_user_by_email(user.email).saved_resources == ["risk"]
  end

  test "unknown bookmark identifiers are rejected", %{conn: conn, user: user} do
    conn = post(conn, ~p"/bookmarks/not-a-resource?locale=en")

    assert redirected_to(conn) == "/en"
    assert Accounts.get_user_by_email(user.email).saved_resources == []
  end

  test "bookmarking requires an account", %{conn: _authenticated_conn} do
    conn = Phoenix.ConnTest.build_conn() |> post(~p"/bookmarks/risk?locale=en")
    assert redirected_to(conn) == "/users/log-in"
  end
end
