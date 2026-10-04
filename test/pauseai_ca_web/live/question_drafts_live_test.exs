defmodule PauseAiCaWeb.QuestionDraftsLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Learning.QuestionBank}
  alias PauseAiCa.Accounts.Scope

  test "LEARN-CMS-DRAFT-02 saved editorial drafts survive reload without entering the public catalogue",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    {:ok, draft} = QuestionBank.create(Scope.for_user(admin))
    conn = log_in_user(conn, admin)
    {:ok, view, _} = live(conn, "/manage/questions/#{draft.id}?locale=en")

    view
    |> form("#question-draft-form", %{
      "question" => %{
        "question" => "Editorial draft",
        "options" => "A\nB",
        "correct" => "1",
        "answer" => "**An explanation**"
      }
    })
    |> render_change()

    {:ok, reloaded, _} = live(conn, "/manage/questions/#{draft.id}?locale=en")
    assert render(reloaded) =~ "Editorial draft"
    assert render(reloaded) =~ "An explanation"
    assert has_element?(reloaded, "#question-save-status", "Saved")
    refute has_element?(reloaded, "section img")
    public = conn |> recycle() |> get("/en/learn") |> html_response(200)
    refute public =~ "Editorial draft"
    plain = log_in_user(build_conn(), user_fixture())
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(plain, "/manage/questions")
  end

  test "LEARN-CMS-03 publish submits the latest form, and status filters survive reload", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)
    {:ok, question} = QuestionBank.create(scope)
    conn = log_in_user(conn, admin)
    {:ok, view, _} = live(conn, "/manage/questions/#{question.id}?locale=en")
    # The Publish control submits the form in the browser; submit it explicitly here.
    view
    |> form("#question-draft-form", %{
      "question" => %{
        "question" => "Latest submitted question",
        "options" => "A\nB",
        "correct" => "1",
        "answer" => "Explanation",
        "source" => "Primary source",
        "url" => "https://example.org/source"
      }
    })
    |> render_submit(%{"intent" => "publish"})

    {:ok, published} = QuestionBank.get(scope, question.id)
    assert published.status == "published"
    public = build_conn() |> get("/en/learn") |> html_response(200)
    assert public =~ "Latest submitted question"
    assert public =~ ~s(data-quiz-correct="1")
    french = build_conn() |> get("/fr/comprendre") |> html_response(200)
    refute french =~ "Latest submitted question"

    {:ok, edited} =
      QuestionBank.save(
        scope,
        published,
        "en",
        Map.put(QuestionBank.values(published, "en"), "question", "Private next edition")
      )

    public = build_conn() |> get("/en/learn") |> html_response(200)
    assert public =~ "Latest submitted question"
    refute public =~ "Private next edition"
    assert QuestionBank.valid_ids([published.concept_id]) == [published.concept_id]
    assert {:ok, _} = PauseAiCa.Accounts.save_resource(admin, published.concept_id)

    assert PauseAiCa.Library.resource(published.concept_id).copy["en"].title ==
             "Latest submitted question"

    # Reload the editor after the independent edit, retaining the reviewed public snapshot.
    {:ok, view, _} = live(conn, "/manage/questions/#{edited.id}?locale=en")

    assert published.published_editions["en"]["question"] == "Latest submitted question"
    assert has_element?(view, "#question-unpublish")
    {:ok, listed, _} = live(conn, "/manage/questions?locale=en&status=published")
    assert has_element?(listed, "#question-status-filter a[aria-current='page']", "Published")
    assert render(listed) =~ "Private next edition"
    view |> form("#question-draft-form") |> render_submit(%{"intent" => "unpublish"})
    view |> element("#question-delete") |> render_click()
    public = build_conn() |> get("/en/learn") |> html_response(200)
    refute public =~ "Latest submitted question"
    refute public =~ "Private next edition"
    assert QuestionBank.valid_ids([published.concept_id]) == []

    assert PauseAiCa.Library.resource(published.concept_id).copy["en"].title ==
             "Latest submitted question"

    {:ok, deleted, _} = live(conn, "/manage/questions?locale=en&status=deleted")
    assert render(deleted) =~ "Private next edition"
    {:ok, restore, _} = live(conn, "/manage/questions/#{question.id}?locale=en")
    restore |> element("#question-restore") |> render_click()
    assert has_element?(restore, "#question-draft-form")
  end
end
