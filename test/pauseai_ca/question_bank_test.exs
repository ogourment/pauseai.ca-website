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

  test "LEARN-CMS-02 publication freezes reviewed content; unpublishing, deletion and restoration preserve audit history" do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)
    {:ok, question} = QuestionBank.create(scope)
    assert {:error, {:publication_invalid, _}} = QuestionBank.publish(scope, question)

    values = %{
      "question" => "A reviewed question",
      "options" => "A\nB",
      "correct" => "0",
      "answer" => "A sourced explanation",
      "source" => "Reviewed primary source",
      "url" => "https://example.org/research",
      "notes" => "Private editorial note"
    }

    {:ok, saved} = QuestionBank.save(scope, question, "en", values)
    assert Enum.all?(QuestionBank.published("en"), &(&1.id != saved.id))
    ordinary = Scope.for_user(user_fixture())
    assert {:error, :unauthorized} = QuestionBank.publish(ordinary, saved)
    {:ok, published} = QuestionBank.publish(scope, saved)
    snapshot = Enum.find(QuestionBank.published("en"), &(&1.id == saved.id))
    assert snapshot.edition["question"] == "A reviewed question"
    refute Map.has_key?(snapshot.edition, "notes")

    {:ok, changed} =
      QuestionBank.save(scope, published, "en", Map.put(values, "question", "A revised question"))

    assert QuestionBank.unpublished_changes?(changed)
    assert Enum.find(QuestionBank.published("en"), &(&1.id == saved.id)) == snapshot
    assert {:error, :stale} = QuestionBank.publish(scope, published)
    assert {:error, :published} = QuestionBank.delete(scope, changed)
    {:ok, republished} = QuestionBank.publish(scope, changed)

    assert Enum.find(QuestionBank.published("en"), &(&1.id == saved.id)).edition["question"] ==
             "A revised question"

    assert {:error, :unauthorized} = QuestionBank.move_to_draft(ordinary, republished)
    {:ok, draft} = QuestionBank.move_to_draft(scope, republished)
    assert Enum.all?(QuestionBank.published("en"), &(&1.id != saved.id))
    assert {:error, :unauthorized} = QuestionBank.delete(ordinary, draft)
    {:ok, deleted} = QuestionBank.delete(scope, draft)
    refute Enum.any?(QuestionBank.list(scope), &(&1.id == saved.id))
    assert Enum.any?(QuestionBank.list(scope, "deleted"), &(&1.id == saved.id))
    assert {:error, :deleted} = QuestionBank.publish(scope, deleted)
    {:ok, restored} = QuestionBank.restore(scope, deleted)
    assert restored.status == "draft"
    assert restored.editions["en"]["question"] == "A revised question"
    assert restored.published_editions["en"]["question"] == "A revised question"
    assert Repo.get!(PauseAiCa.Learning.QuestionDraft, saved.id).deleted_at == nil
    assert Repo.aggregate(QuestionRevision, :count) == 7
  end
end
