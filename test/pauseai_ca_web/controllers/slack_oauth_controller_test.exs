defmodule PauseAiCaWeb.SlackOAuthControllerTest do
  use PauseAiCaWeb.ConnCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{SlackFixtures, Chat.Slack}
  alias PauseAiCa.Accounts.Scope

  test "actual connect/callback routes retain the authenticated browser binding", %{conn: conn} do
    saved = SlackFixtures.configure!()
    on_exit(fn -> SlackFixtures.restore!(saved) end)
    user = user_fixture()
    conn = conn |> log_in_user(user) |> post("/community/slack/connect")
    uri = conn |> redirected_to() |> URI.parse()
    assert uri.host == "slack.com"
    assert uri.path == "/oauth/v2/authorize"
    params = URI.decode_query(uri.query)
    assert get_session(conn, :slack_link_nonce)
    assert params["user_scope"] =~ "chat:write"

    conn =
      get(recycle(conn), "/community/slack/callback", %{
        state: params["state"],
        code: "synthetic-code"
      })

    assert redirected_to(conn) =~ "/community/slack"
    assert get_session(conn, :slack_link_nonce) == nil
    assert {:ok, %{provider_user_id: "U1"}} = Slack.link(Scope.for_user(user))

    conn =
      get(recycle(conn), "/community/slack/callback", %{
        state: params["state"],
        code: "synthetic-code"
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "could not be verified"
  end
end
