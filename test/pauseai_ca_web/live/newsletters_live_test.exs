defmodule PauseAiCaWeb.NewslettersLiveTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Newsletters, Repo, Accounts}

  test "admin records an external unsubscribe request through the UI", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    {:ok, view, _} = live(log_in_user(conn, admin), "/manage/mail/newsletters?locale=en")

    view
    |> form("#newsletter-withdrawal",
      withdrawal: %{email: "external@example.org", reason: "Received by email today"}
    )
    |> render_submit()

    assert_patch(view, "/manage/mail/newsletters?locale=en&q=external%40example.org")
    assert render(view) =~ "Unsubscribe request recorded"
    refute Newsletters.outreach_eligible?("external@example.org")
  end

  test "superadmin sees consent exclusions and shareable geography; revocation closes access", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)

    {:ok, first} =
      Newsletters.request_signup("montreal@example.org", %{consent: true, region: "Montréal"})

    {:ok, _} = Newsletters.confirm(first.confirmation_token)
    {:ok, _} = Newsletters.observe_legacy(scope, "legacy@example.org", %{"provider" => "brevo"})
    conn = log_in_user(conn, admin)
    {:ok, view, html} = live(conn, "/manage/mail/newsletters?locale=en")
    assert html =~ "montreal@example.org"
    assert html =~ "legacy@example.org"
    assert has_element?(view, "#newsletter-counts", "Legacy evidence to review")

    view
    |> form("#newsletter-filters", filters: %{region: "Montréal", q: "", per: "10"})
    |> render_submit()

    assert_patch(view, "/manage/mail/newsletters?locale=en&page=1&per=10&q=&region=Montr%C3%A9al")
    refute render(view) =~ "legacy@example.org"

    view
    |> element("#newsletter-#{first.subscription.id} button", "Consent history")
    |> render_click()

    assert has_element?(view, "#newsletter-history", "Signup confirmed")
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

    view
    |> element("#newsletter-#{first.subscription.id} button", "Consent history")
    |> render_click()

    assert_redirect(view, "/dashboard")
  end

  test "ordinary account cannot inspect newsletter audience", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/manage/mail/newsletters")
  end
end
