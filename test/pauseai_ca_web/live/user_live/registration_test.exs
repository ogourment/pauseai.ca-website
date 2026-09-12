defmodule PauseAiCaWeb.UserLive.RegistrationTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts

  test "registration shares the recoverable email entry", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/users/register")
    assert has_element?(view, "#registration_form")
    assert render(view) =~ "Create an account"
  end

  test "already logged-in users do not create a second account", %{conn: conn} do
    result =
      conn
      |> log_in_user(user_fixture())
      |> live(~p"/users/register")
      |> follow_redirect(conn, ~p"/")

    assert {:ok, _conn} = result
  end

  test "invalid submission retains the email and task", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/users/register?bookmark=risk")
    view |> form("#registration_form", user: %{email: "with spaces"}) |> render_submit()
    assert has_element?(view, "#registration_form", "must have the @ sign")
    assert has_element?(view, "#registration_form_email[value='with spaces']")
  end

  test "delivered confirmation resumes the task, without applying it before ownership", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/users/register?bookmark=risk&locale=fr")
    email = unique_user_email()
    view |> form("#registration_form", user: %{email: email}) |> render_submit()
    assert has_element?(view, "#account-email-pending")
    assert Accounts.get_user_by_email(email).saved_resources == []
    assert_receive {:email, delivered}
    [link] = Regex.run(~r{https?://[^\s]+/users/log-in/[^\s]+}, delivered.text_body)
    uri = URI.parse(link)
    params = URI.decode_query(uri.query)
    token = uri.path |> String.split("/") |> List.last()
    conn = post(conn, ~p"/users/log-in", user: %{token: token, flow: params["flow"]})
    assert redirected_to(conn) == "/fr/comprendre"
    assert Accounts.get_user_by_email(email).saved_resources == ["risk"]
    assert Accounts.get_user_by_email(email).confirmed_at
  end

  test "existing address receives generic feedback and keeps its original resources", %{
    conn: conn
  } do
    user = user_fixture()
    assert_receive {:email, _fixture_confirmation}
    {:ok, user} = Accounts.save_resource(user, "pause")
    {:ok, view, _} = live(conn, ~p"/users/register?bookmark=risk")
    view |> form("#registration_form", user: %{email: user.email}) |> render_submit()
    assert has_element?(view, "#account-email-pending")
    assert Accounts.get_user_by_email(user.email).saved_resources == ["pause"]
    refute render(view) =~ "already exists"
    assert_receive {:email, delivered}
    assert delivered.subject =~ "Your sign-in link"
  end
end
