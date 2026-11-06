defmodule PauseAiCaWeb.UserSessionControllerTest do
  use PauseAiCaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "reauthentication ignores a forged readonly email even with valid other-account credentials",
         %{conn: conn, user: user} do
      user = set_password(user)
      other = user_fixture() |> set_password()

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/log-in", %{
          "user" => %{"email" => other.email, "password" => valid_user_password()}
        })

      token = get_session(conn, :user_token)
      assert {authenticated, _} = Accounts.get_user_by_session_token(token)
      assert authenticated.id == user.id
      refute authenticated.id == other.id
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_pause_ai_ca_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      refute Phoenix.Flash.get(conn.assigns.flash, :info)
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "That email and password do not match."

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "You're in — your email is confirmed."

      assert Accounts.get_user!(user.id).confirmed_at

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "This sign-in link is invalid or has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "You're signed out."
    end

    test "explicit switch revokes the current session and returns only to editable hinted login",
         %{conn: conn, user: user} do
      hint = "other-review@example.org"

      conn =
        conn
        |> log_in_user(user)
        |> put_session(:user_return_to, "https://untrusted.example/redirect")
        |> put_session("phoenix_flash", %{
          "email" => user.email,
          "error" => "Earlier password error"
        })

      token = get_session(conn, :user_token)

      conn =
        delete(conn, ~p"/users/log-out", %{
          switch_account: "true",
          email: hint,
          locale: "fr",
          return_to: "https://untrusted.example/redirect"
        })

      target = redirected_to(conn)
      assert URI.parse(target).path == "/users/log-in"
      assert URI.decode_query(URI.parse(target).query) == %{"email" => hint, "locale" => "fr"}
      refute get_session(conn, :user_token)
      refute get_session(conn, :user_return_to)
      refute Phoenix.Flash.get(conn.assigns.flash, :email)
      refute Phoenix.Flash.get(conn.assigns.flash, :info)
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
      refute Accounts.get_user_by_session_token(token)
      assert %{max_age: 0} = conn.resp_cookies["_pause_ai_ca_web_user_remember_me"]
      {:ok, view, _} = conn |> recycle() |> live(target)
      assert has_element?(view, "#login_form_magic_email[value='#{hint}']:not([readonly])")
      refute has_element?(view, "#switch-account")
      refute Accounts.get_user_by_email(hint)
    end

    test "malformed or oversized switch hints cannot affect the fixed login destination", %{
      conn: conn,
      user: user
    } do
      for hint <- [
            "not-an-email",
            "valid@example.org\r\nBcc:extra@example.org",
            String.duplicate("a", 161),
            %{"nested" => "value"}
          ] do
        result =
          conn
          |> recycle()
          |> log_in_user(user)
          |> delete(~p"/users/log-out", %{
            "switch_account" => "true",
            "email" => hint,
            "locale" => "https://untrusted.example",
            "return_to" => "https://untrusted.example"
          })

        assert redirected_to(result) == "/users/log-in?locale=en"
        refute get_session(result, :user_token)
      end
    end

    test "account switch requires CSRF and cannot revoke a session without it", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      token = get_session(conn, :user_token)

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        conn
        |> put_private(:plug_skip_csrf_protection, false)
        |> delete(~p"/users/log-out", %{switch_account: "true"})
      end

      assert Accounts.get_user_by_session_token(token)
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "You're signed out."
    end
  end
end
