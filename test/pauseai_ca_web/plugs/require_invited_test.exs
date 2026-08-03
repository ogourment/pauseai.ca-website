defmodule PauseAiCaWeb.Plugs.RequireInvitedTest do
  @moduledoc """
  The staging gate exists because the campaign page can send email to a member
  of parliament. Left open on a public domain, that is an unauthenticated relay
  pointed at Parliament and signed by our own domain.
  """

  use PauseAiCaWeb.ConnCase, async: false

  import PauseAiCa.AccountsFixtures

  setup do
    original = Application.get_env(:pauseai_ca, :require_invited, false)
    Application.put_env(:pauseai_ca, :require_invited, true)
    on_exit(fn -> Application.put_env(:pauseai_ca, :require_invited, original) end)
    :ok
  end

  describe "when the gate is on" do
    test "an anonymous visitor cannot reach the campaign page", %{conn: conn} do
      conn = get(conn, ~p"/en/warning-shot")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "an anonymous visitor cannot reach the home page", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/en")) == ~p"/users/log-in"
    end

    test "the sign-in routes stay reachable, or nobody could ever get in", %{conn: conn} do
      assert html_response(get(conn, ~p"/users/log-in"), 200)
      assert html_response(get(conn, ~p"/users/register"), 200)
    end

    test "the health endpoint stays reachable for the deploy script", %{conn: conn} do
      assert conn |> get(~p"/health") |> json_response(200)
    end

    test "a signed-in visitor passes through", %{conn: conn} do
      conn =
        conn
        |> log_in_user(user_fixture())
        |> get(~p"/en/warning-shot")

      assert html_response(conn, 200) =~ "Warning Shot"
    end

    test "the visitor is returned to where they were headed", %{conn: conn} do
      conn = get(conn, ~p"/en/learn")

      assert get_session(conn, :user_return_to) == "/en/learn"
    end
  end

  describe "when the gate is off" do
    setup do
      Application.put_env(:pauseai_ca, :require_invited, false)
      :ok
    end

    test "the public site is public", %{conn: conn} do
      assert html_response(get(conn, ~p"/en/warning-shot"), 200)
    end
  end
end
