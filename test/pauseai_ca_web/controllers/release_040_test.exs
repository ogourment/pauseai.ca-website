defmodule PauseAiCaWeb.Release040Test do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  alias PauseAiCa.{AccountsFixtures, Repo}
  alias PauseAiCa.Engagement.DailyVisit

  setup do
    previous = Application.get_env(:pauseai_ca, :public_origins)

    Application.put_env(:pauseai_ca, :public_origins, %{
      "en" => "https://pauseai.example",
      "fr" => "https://pauseia.example"
    })

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pauseai_ca, :public_origins, previous),
        else: Application.delete_env(:pauseai_ca, :public_origins)
    end)
  end

  test "French hostname chooses French, preserves the root query and uses a trusted email origin",
       %{conn: conn} do
    conn = %{conn | host: "pauseia.example"}
    assert redirected_to(get(conn, "/?source=test")) == "/fr?source=test"
    {:ok, page, html} = live(recycle(conn), "/users/register")
    assert html =~ "Créer un compte"
    assert html =~ ~s(lang="fr")
    page |> form("#registration_form", user: %{email: "domain040@example.org"}) |> render_submit()
    assert_receive {:email, email}
    assert email.text_body =~ "https://pauseia.example/users/log-in/"
    refute email.text_body =~ "https://pauseai.example/users/log-in/"

    assert PauseAiCaWeb.Site.url("fr", "/fr/signal-d-alarme") ==
             "https://pauseia.example/fr/signal-d-alarme"
  end

  test "untrusted Host cannot become an outgoing sign-in link", %{conn: conn} do
    {:ok, page, _html} = live(%{conn | host: "attacker.invalid"}, "/users/register?locale=fr")

    page
    |> form("#registration_form", user: %{email: "safe-domain040@example.org"})
    |> render_submit()

    assert_receive {:email, email}
    assert email.text_body =~ "https://pauseia.example/"
    refute email.text_body =~ "attacker.invalid"
  end

  test "hidden volunteer page redirects members to their localized account profile", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    for {locale, path} <- [{"fr", "/fr/profil"}, {"en", "/en/profile"}] do
      response = conn |> log_in_user(user) |> get("/volunteer-profile?locale=" <> locale)
      assert redirected_to(response) == path
      html = conn |> log_in_user(user) |> get(path) |> html_response(200)
      refute html =~ "href=\"/volunteer-profile"
    end
  end

  test "browser exclusion survives sign-out, can be revoked, and does not suppress another browser",
       %{conn: conn} do
    admin =
      AccountsFixtures.user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

    conn = conn |> log_in_user(admin) |> post("/admin/visit-preferences", %{excluded: "true"})
    assert redirected_to(conn) == "/admin/dashboard"
    conn = conn |> recycle() |> delete("/users/log-out")
    conn = conn |> recycle() |> put_private(:record_visits, true) |> post("/engagement/visits")
    assert Repo.aggregate(DailyVisit, :sum, :count) in [nil, 0]
    build_conn() |> put_private(:record_visits, true) |> post("/engagement/visits")
    assert Decimal.eq?(Repo.aggregate(DailyVisit, :sum, :count), 1)

    conn =
      conn
      |> recycle()
      |> log_in_user(admin)
      |> post("/admin/visit-preferences", %{excluded: "false"})

    conn = conn |> recycle() |> delete("/users/log-out")
    conn |> recycle() |> put_private(:record_visits, true) |> post("/engagement/visits")
    assert Decimal.eq?(Repo.aggregate(DailyVisit, :sum, :count), 2)
  end

  test "ordinary members cannot change the admin browser preference", %{conn: conn} do
    response =
      conn
      |> log_in_user(AccountsFixtures.user_fixture())
      |> post("/admin/visit-preferences", %{excluded: "true"})

    assert response.status == 403
    refute Map.has_key?(response.resp_cookies, "_pauseai_exclude_visits")
  end
end
