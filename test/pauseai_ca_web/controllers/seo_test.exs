defmodule PauseAiCaWeb.SEOTest do
  use PauseAiCaWeb.ConnCase

  setup do
    previous = Application.get_env(:pauseai_ca, :public_origins)

    Application.put_env(:pauseai_ca, :public_origins, %{
      "en" => "https://pauseai.ca",
      "fr" => "https://pauseia.ca"
    })

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pauseai_ca, :public_origins, previous),
        else: Application.delete_env(:pauseai_ca, :public_origins)
    end)
  end

  test "sitemap follows immutable CMS publication and excludes unfinished translations", %{
    conn: conn
  } do
    user =
      PauseAiCa.AccountsFixtures.user_fixture()
      |> Ecto.Changeset.change(superadmin: true)
      |> PauseAiCa.Repo.update!()

    scope = PauseAiCa.Accounts.Scope.for_user(user)
    {:ok, article} = PauseAiCa.Blog.create(scope, "seo-publication")

    payload =
      PauseAiCa.Blog.empty_payload()
      |> Map.put("en", %{
        "markdown" => "# Public title\n\nPublished **summary**.\n\n## Details\n\nMore detail."
      })

    {:ok, article} = PauseAiCa.Blog.save(scope, article, payload)
    refute get(conn, "/sitemap.xml").resp_body =~ "seo-publication"
    {:ok, article} = PauseAiCa.Blog.publish(scope, article)
    xml = get(conn, "/sitemap.xml").resp_body
    assert xml =~ "https://pauseai.ca/en/blog/seo-publication"
    refute xml =~ "/fr/blogue/seo-publication"
    html = conn |> get("/en/blog/seo-publication") |> html_response(200)
    assert html =~ ~s(content="Published summary.")
    {:ok, _} = PauseAiCa.Blog.unpublish(scope, article)
    refute get(conn, "/sitemap.xml").resp_body =~ "seo-publication"
  end

  test "public pages expose localized crawler metadata using configured origins", %{conn: conn} do
    for {path, language, title} <- [
          {"/en", "en-CA", "PauseAI Canada — A global pause on advanced AI"},
          {"/fr", "fr-CA", "PauseIA Canada — Une pause mondiale de l’IA avancée"}
        ] do
      html = conn |> get(path <> "?utm_source=test") |> html_response(200)
      document = LazyHTML.from_document(html)
      assert LazyHTML.text(LazyHTML.query(document, "title")) == title
      assert [_] = LazyHTML.query(document, "meta[name=description]") |> LazyHTML.to_tree()
      assert html =~ ~s(hreflang="#{language}")

      assert html =~
               ~s(rel="canonical" href="#{if language == "en-CA", do: "https://pauseai.ca/en", else: "https://pauseia.ca/fr"}")

      assert html =~ ~s(property="og:image")
      assert html =~ ~s(name="twitter:card" content="summary_large_image")

      [script] =
        LazyHTML.query(document, "script[type='application/ld+json']")
        |> LazyHTML.text()
        |> Jason.decode!()
        |> Map.fetch!("@graph")
        |> Enum.filter(&(&1["@type"] == "Organization"))

      assert script["name"] == "PauseAI Canada"
      refute html =~ "canonical\" href=\"http://www.example.com"
      refute html =~ "canonical\" href=\"https://evil.example"
    end
  end

  test "sitemap accepts XML clients and excludes private workflows", %{conn: conn} do
    response = conn |> put_req_header("accept", "application/xml") |> get("/sitemap.xml")
    assert response.status == 200
    xml = response.resp_body
    assert xml =~ "<urlset"
    assert xml =~ "/en/about</loc>"
    refute xml =~ "/admin"
    refute xml =~ "/manage"
    refute xml =~ "/users"
    refute xml =~ "<loc>https://pauseia.ca"
  end

  test "private pages have no canonical or publication metadata", %{conn: conn} do
    html = conn |> get("/users/log-in") |> html_response(200)
    assert html =~ ~s(name="robots" content="noindex, nofollow")
    refute html =~ ~s(rel="canonical")
    refute html =~ ~s(type="application/ld+json")
  end

  test "legacy and root URLs redirect permanently", %{conn: conn} do
    for {old, target} <- [{"/", "/en"}, {"/canada.html", "/en"}, {"/fr/learn", "/fr/comprendre"}] do
      assert redirected_to(get(conn, old), 301) == target
    end
  end
end
