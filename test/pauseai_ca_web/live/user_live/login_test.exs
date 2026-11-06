defmodule PauseAiCaWeb.UserLive.LoginTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts

  test "a review link prefills email without requesting mail", %{conn: conn} do
    {:ok, view, _} = live(conn, "/users/log-in?email=reviewer%40example.org")
    assert has_element?(view, "#login_form_magic_email[value='reviewer@example.org']")
    assert has_element?(view, "#login_form_password_email[value='reviewer@example.org']")
    refute_received {:email, _}
  end

  test "combined email entry explains account value and stays recoverable", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/users/log-in")
    assert has_element?(view, "#login_form_magic")
    assert has_element?(view, "#continue-browsing")
    assert render(view) =~ "Use the email address you want for your account"
    refute has_element?(view, "#account-email-pending")
  end

  test "new email receives confirmation and the same pending message as an existing email", %{
    conn: conn
  } do
    email = unique_user_email()
    {:ok, view, _} = live(conn, ~p"/users/log-in?from=header")
    view |> form("#login_form_magic", user: %{email: email}) |> render_submit()
    assert has_element?(view, "#account-email-pending", "Check your email")
    assert %{confirmed_at: nil, signup_entry_point: "header"} = Accounts.get_user_by_email(email)
    assert_receive {:email, delivered}
    assert delivered.to == [{"", email}]
    assert delivered.subject =~ "Confirm your account"
    refute render(view) =~ "already exists"
    view |> form("#login_form_magic", user: %{email: email}) |> render_submit()
    assert has_element?(view, "#account-email-pending", "Check your email")
    assert_receive {:email, _retry}
  end

  test "existing member receives a sign-in link without a new account", %{conn: conn} do
    user = user_fixture()
    assert_receive {:email, _fixture_confirmation}
    {:ok, view, _} = live(conn, ~p"/users/log-in")
    view |> form("#login_form_magic", user: %{email: user.email}) |> render_submit()
    assert has_element?(view, "#account-email-pending")
    assert_receive {:email, delivered}
    assert delivered.subject =~ "Your sign-in link"
    assert Accounts.get_user_by_email(user.email).id == user.id
  end

  test "invalid email has inline errors and retains the value", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/users/log-in")
    view |> form("#login_form_magic", user: %{email: "with spaces"}) |> render_submit()
    assert has_element?(view, "#login_form_magic", "must have the @ sign")
    assert has_element?(view, "#login_form_magic_email[value='with spaces']")
  end

  test "password fallback still logs in existing members", %{conn: conn} do
    user = user_fixture() |> set_password()
    {:ok, view, _} = live(conn, ~p"/users/log-in")

    form =
      form(view, "#login_form_password",
        user: %{email: user.email, password: valid_user_password(), remember_me: true}
      )

    conn = submit_form(form, conn)
    assert redirected_to(conn) == ~p"/"
  end

  test "password failure retains safe generic feedback", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/users/log-in")

    form =
      form(view, "#login_form_password", user: %{email: "test@example.org", password: "wrong"})

    render_submit(form)
    conn = follow_trigger_action(form, conn)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "do not match"
  end

  test "reauthentication explains the current identity and offers an explicit localized DELETE switch",
       %{conn: conn} do
    user = user_fixture()
    hint = "other-review@example.org"

    {:ok, view, html} =
      live(log_in_user(conn, user), ~p"/users/log-in?#{%{email: hint, locale: "fr"}}")

    assert has_element?(view, "#reauth-current-account", user.email)

    assert has_element?(
             view,
             "#switch-account[data-method='delete'][data-csrf]",
             "Utiliser un autre compte"
           )

    [href] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#switch-account")
      |> LazyHTML.attribute("href")

    assert URI.parse(href).path == "/users/log-out"

    assert URI.decode_query(URI.parse(href).query) == %{
             "switch_account" => "true",
             "email" => hint,
             "locale" => "fr"
           }

    assert has_element?(view, "#login_form_magic_email[readonly][value='#{user.email}']")
    assert has_element?(view, "#login_form_password_email[readonly][value='#{user.email}']")
    refute Accounts.get_user_by_email(hint)
  end

  test "a signed-out login never renders the account-switch control", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/users/log-in")
    refute has_element?(view, "#switch-account")
    refute has_element?(view, "#login_form_magic_email[readonly]")
  end

  test "privileged reauthentication uses the current account, not a forged readonly address", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), ~p"/users/log-in")
    assert has_element?(view, "#login_form_magic_email[readonly][value='#{user.email}']")
    assert render(view) =~ "Confirm it is you"
    view |> form("#login_form_magic", user: %{email: "forged@example.org"}) |> render_change()
    assert has_element?(view, "#login_form_magic_email[readonly][value='#{user.email}']")
    view |> form("#login_form_magic", user: %{email: "forged@example.org"}) |> render_submit()
    assert_receive {:email, delivered}
    assert delivered.to == [{"", user.email}]
    refute Accounts.get_user_by_email("forged@example.org")
  end
end
