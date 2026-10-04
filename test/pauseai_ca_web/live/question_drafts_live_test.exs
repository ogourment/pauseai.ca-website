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
end
