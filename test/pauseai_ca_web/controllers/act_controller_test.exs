defmodule PauseAiCaWeb.ActControllerTest do
  use PauseAiCaWeb.ConnCase, async: true

  import PauseAiCa.AccountsFixtures

  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Engagement
  alias PauseAiCa.Engagement.Action

  describe "leaving for PauseAI Global" do
    test "join sends an English visitor to the prefilled form", %{conn: conn} do
      conn = get(conn, ~p"/act/join?locale=en")

      assert redirected_to(conn) =~ "pauseai.info/embed/onboarding-form"
      assert redirected_to(conn) =~ "country=Canada"
      assert redirected_to(conn) =~ "languages=English"
    end

    test "join sends a French visitor to the French form", %{conn: conn} do
      assert get(conn, ~p"/act/join?locale=fr") |> redirected_to() =~ "languages=French"
    end

    test "sign sends everyone to the statement", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/act/sign?locale=en")) == "https://pauseai.info/statement"
    end

    test "an unknown destination does not redirect off-site", %{conn: conn} do
      conn = get(conn, ~p"/act/evil?locale=en")

      assert redirected_to(conn) == ~p"/en"
    end
  end

  describe "recording the departure" do
    setup do
      user = user_fixture()
      %{user: user, scope: Scope.for_user(user)}
    end

    test "a signed-in visitor gets an unconfirmed action", %{conn: conn, user: user, scope: scope} do
      conn |> log_in_user(user) |> get(~p"/act/join?locale=en")

      assert [action] = Engagement.list_actions(scope)
      assert action.action_type == "joined"
      # We watched them leave, which is not the same as watching them finish.
      assert Action.pending?(action)
    end

    test "signing is recorded separately from joining", %{conn: conn, user: user, scope: scope} do
      conn |> log_in_user(user) |> get(~p"/act/sign?locale=en")

      assert [action] = Engagement.list_actions(scope)
      assert action.action_type == "signed"
    end

    test "the reading page is not written to anyone's log", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      conn |> log_in_user(user) |> get(~p"/act/actions?locale=en")

      assert Engagement.list_actions(scope) == []
    end

    test "an anonymous visitor is redirected and nothing is recorded", %{conn: conn} do
      conn = get(conn, ~p"/act/join?locale=en")

      assert redirected_to(conn) =~ "pauseai.info"
    end
  end
end
