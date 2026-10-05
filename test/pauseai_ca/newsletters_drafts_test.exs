defmodule PauseAiCa.NewslettersDraftsTest do
  use PauseAiCa.DataCase, async: true
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Newsletters, Accounts}
  alias PauseAiCa.Newsletters.Drafts

  test "content and geography persist, stale edits retain current content, archive is reversible with no consent or account effect" do
    author = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(author)
    accounts = Repo.aggregate(Accounts.User, :count)
    {:ok, draft} = Drafts.create(scope)

    {:ok, saved} =
      Drafts.save(scope, draft, %{
        "subject" => "Protest recap",
        "source" => "# Montréal",
        "region" => "Montréal"
      })

    assert {:error, :stale} = Drafts.save(scope, draft, %{"source" => "stale overwrite"})
    assert {:ok, ^saved} = Drafts.get(scope, saved.id)
    {:ok, archived} = Drafts.archive(scope, saved)
    assert {:ok, []} = Drafts.list(scope)
    assert {:ok, [^archived]} = Drafts.list(scope, true)
    assert {:error, :archived} = Drafts.save(scope, archived, %{"source" => "not editable"})
    {:ok, restored} = Drafts.archive(scope, archived, false)
    assert restored.source == "# Montréal"
    assert {:ok, [^restored]} = Drafts.list(scope)
    assert Repo.aggregate(Newsletters.Subscription, :count) == 0
    assert Repo.aggregate(Accounts.User, :count) == accounts
  end

  test "other authors and revoked actors cannot read or change a private draft" do
    author = user_fixture() |> change(superadmin: true) |> Repo.update!()
    other = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(author)
    outsider = Accounts.Scope.for_user(other)
    {:ok, draft} = Drafts.create(scope)
    assert {:error, :unauthorized} = Drafts.get(outsider, draft.id)
    assert {:error, :unauthorized} = Drafts.save(outsider, draft, %{"source" => "foreign edit"})
    author |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Drafts.archive(scope, draft)
    assert {:error, :unauthorized} = Drafts.list(scope)
    assert Repo.get!(Newsletters.Draft, draft.id).revision == 1
  end
end
