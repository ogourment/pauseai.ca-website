defmodule PauseAiCaWeb.UserLive.RegistrationTest do
  use PauseAiCaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Create an account"
      assert html =~ "Sign in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces"})

      assert result =~ "Create an account"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Check #{email} for your secure sign-in link."
    end

    test "saves the bookmarked argument with the email account", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register?bookmark=risk")
      email = unique_user_email()

      lv
      |> form("#registration_form", user: valid_user_attributes(email: email))
      |> render_submit()

      assert Accounts.get_user_by_email(email).saved_resources == ["risk"]
    end

    test "saves question progress with the email account", %{conn: conn} do
      {:ok, lv, _html} =
        live(conn, ~p"/users/register?from=questions&risk=4&pause=3&coordination=2")

      email = unique_user_email()

      lv
      |> form("#registration_form", user: valid_user_attributes(email: email))
      |> render_submit()

      assert Accounts.get_user_by_email(email).belief_answers == %{
               "risk" => "4",
               "pause" => "3",
               "coordination" => "2"
             }
    end

    test "switches an existing email to secure sign-in and preserves the bookmark", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register?bookmark=risk")

      user = user_fixture(%{email: "test@email.com"})

      {:ok, _login_live, html} =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "An account already exists for #{user.email}."
      refute html =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Sign in"
    end
  end
end
