defmodule PauseAiCa.QuestionBankTest do
  use PauseAiCa.DataCase
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Learning.{QuestionBank, QuestionRevision}

  test "LEARN-CMS-DRAFT-01 organizers share bilingual drafts, audit edits and reject stale/unsafe updates" do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(scope, %{"name" => "Quiz reviewers"})
    editor = user_fixture()
    {:ok, _} = Volunteers.assign_manager(scope, group.id, editor.email)
    reviewer = Scope.for_user(editor)
    {:ok, draft} = QuestionBank.create(scope)

    en = %{
      "question" => "Can a petition require a response?",
      "options" => "Yes\nNo",
      "correct" => "0",
      "answer" => "**Official response**, without a guaranteed policy change.",
      "url" => "https://www.ourcommons.ca/petitions/en/home/index"
    }

    {:ok, saved} = QuestionBank.save(reviewer, draft, "en", en)
    {:ok, shared} = QuestionBank.get(scope, saved.id)
    assert shared.editions["en"]["question"] == en["question"]
    assert shared.status == "draft"
    assert {:error, :stale} = QuestionBank.save(scope, draft, "en", %{"question" => "Old copy"})

    {:ok, fr} =
      QuestionBank.save(scope, saved, "fr", %{
        "question" => "Une pétition exige-t-elle une réponse ?"
      })

    assert fr.editions["en"] == saved.editions["en"]
    assert fr.editions["fr"]["question"] =~ "pétition"

    assert {:error, :invalid} =
             QuestionBank.save(scope, fr, "en", Map.put(en, "url", "javascript:alert(1)"))

    assert Repo.aggregate(QuestionRevision, :count) == 2
    ordinary = Scope.for_user(user_fixture())
    assert QuestionBank.list(ordinary) == []
    assert {:error, :unauthorized} = QuestionBank.save(ordinary, fr, "en", en)
    assert {:error, :unauthorized} = QuestionBank.create(ordinary)
    assert {:error, :unauthorized} = QuestionBank.get(ordinary, fr.id)
  end
end
