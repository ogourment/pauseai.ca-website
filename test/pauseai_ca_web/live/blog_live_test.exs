defmodule PauseAiCaWeb.BlogLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Blog, Repo}
  alias PauseAiCa.Accounts.Scope

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{admin: admin, scope: Scope.for_user(admin), conn: log_in_user(conn, admin)}
  end

  defp payload do
    Map.new(~w(en fr), fn locale ->
      {locale,
       %{
         "markdown" =>
           "# Title #{locale}\n\nShort #{locale}\n\n## Detail #{locale}\n\nDetails #{locale}\n\n### Complete #{locale}\n\nComplete #{locale}"
       }}
    end)
  end

  test "readers get Markdown sections and old depth links still open the hierarchy", %{
    conn: conn,
    scope: scope
  } do
    {:ok, article} = Blog.create(scope, "reader-choice")
    {:ok, article} = Blog.save(scope, article, payload())
    {:ok, view, _} = live(conn, "/en/blog")
    refute render(view) =~ "Title en"
    {:ok, _} = Blog.publish(scope, article)
    {:ok, index, _} = live(conn, "/en/blog")
    assert has_element?(index, "h2", "Title en")
    assert render(index) =~ "Short en"
    {:ok, view, _} = live(conn, "/en/blog/reader-choice")
    assert has_element?(view, "#blog-intro", "Short en")
    assert has_element?(view, "#blog-section-detail-en #blog-section-complete-en")
    refute has_element?(view, "details[open]")
    {:ok, details, _} = live(conn, "/en/blog/reader-choice?depth=details")
    assert has_element?(details, "#blog-section-detail-en[open]")
    refute has_element?(details, "#blog-section-complete-en[open]")
    {:ok, fr, _} = live(conn, "/fr/blogue/reader-choice?depth=full")
    assert has_element?(fr, "h1", "Title fr")
    assert has_element?(fr, "#blog-section-detail-fr[open] #blog-section-complete-fr[open]")
  end

  test "editor creation, save, preview and publication use independent steps", %{conn: conn} do
    {:ok, view, _} = live(conn, "/manage/blog?locale=en")
    result = view |> form("#blog-create", article: %{slug: "editor-flow"}) |> render_submit()
    {:ok, view, _} = follow_redirect(result, conn)
    values = %{"article" => payload()}
    view |> form("#blog-editor", values) |> render_change()
    assert has_element?(view, "#blog-publish[disabled]")
    view |> form("#blog-editor", values) |> render_submit(%{"intent" => "preview"})
    assert has_element?(view, "#blog-preview", "Complete fr")
    assert Blog.published() == []
    view |> form("#blog-editor", values) |> render_submit(%{"intent" => "save"})
    assert has_element?(view, "#blog-save-status", "Saved")
    view |> form("#blog-editor") |> render_submit(%{"intent" => "publish"})
    assert Blog.published("editor-flow")
    view |> element("button[phx-click=unpublish]") |> render_click()
    assert Blog.published("editor-flow") == nil
  end

  test "untranslated public edition is unavailable and malformed editor events are harmless", %{
    conn: conn,
    scope: scope
  } do
    {:ok, article} = Blog.create(scope, "english-only")
    payload = Blog.empty_payload() |> Map.put("en", payload()["en"])
    {:ok, article} = Blog.save(scope, article, payload)
    {:ok, _} = Blog.publish(scope, article)
    {:ok, french, _} = live(conn, "/fr/blogue/english-only")
    assert has_element?(french, "h1", "Article indisponible")
    refute has_element?(french, "#blog-article")
    {:ok, english, _} = live(conn, "/en/blog/english-only")
    assert has_element?(english, "a[href='/fr/blogue']")
    {:ok, index, _} = live(conn, "/manage/blog?locale=en")
    render_hook(index, "edit", %{"article" => "invalid"})
    render_hook(index, "submit", %{"article" => %{}})
    render_hook(index, "restore", %{"id" => []})
    assert has_element?(index, "#blog-create")
    {:ok, editor, _} = live(conn, "/manage/blog/#{article.id}?locale=en")
    render_hook(editor, "edit", %{"article" => %{"en" => %{"title" => %{}}}})
    send(editor.pid, {:markdown_editor_changed, "blog-en-markdown", payload["en"]["markdown"]})
    assert has_element?(editor, "#blog-save-status", "Saved")
  end

  test "unsaved body edits survive blocked publication actions until saved", %{
    conn: conn,
    scope: scope
  } do
    {:ok, article} = Blog.create(scope, "protect-unsaved")
    {:ok, article} = Blog.save(scope, article, payload())
    {:ok, article} = Blog.publish(scope, article)
    {:ok, view, _} = live(conn, "/manage/blog/#{article.id}?locale=en")

    values = %{
      "article" => put_in(payload(), ["en", "markdown"], "# Changed\n\nUnsaved complete body")
    }

    view |> form("#blog-editor", values) |> render_change()
    assert has_element?(view, "button[phx-click=unpublish][disabled]")
    assert has_element?(view, "button[phx-click=archive][disabled]")
    render_hook(view, "unpublish", %{})
    render_hook(view, "archive", %{})
    assert Blog.published(article.slug).payload["en"]["markdown"] == payload()["en"]["markdown"]
    assert has_element?(view, "#blog-en-markdown-source", "Unsaved complete body")
    view |> form("#blog-editor", values) |> render_submit(%{"intent" => "save"})
    refute has_element?(view, "button[phx-click=unpublish][disabled]")
    view |> element("button[phx-click=unpublish]") |> render_click()
    assert Blog.published(article.slug) == nil
    {:ok, saved} = Blog.get(scope, article.id)
    assert saved.payload["en"]["markdown"] == "# Changed\n\nUnsaved complete body"
  end

  test "role revocation clears the connected editor", %{conn: conn, admin: admin} do
    {:ok, view, _} = live(conn, "/manage/blog?locale=en")
    Repo.update!(Ecto.Changeset.change(admin, superadmin: false))
    view |> form("#blog-create", article: %{slug: "forbidden"}) |> render_submit()
    assert_redirect(view, "/dashboard")
    assert Blog.published() == []
  end
end
