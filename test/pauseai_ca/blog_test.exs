defmodule PauseAiCa.BlogTest do
  use PauseAiCa.DataCase
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Blog, Repo}
  alias PauseAiCa.Accounts.Scope

  setup do
    user = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{scope: Scope.for_user(user), user: user}
  end

  def payload do
    Map.new(~w(en fr), fn locale ->
      {locale,
       %{
         "title" => "Title #{locale}",
         "summary" => "Short #{locale}",
         "details" => "## Detail #{locale}",
         "full" => "Complete #{locale}"
       }}
    end)
  end

  test "public snapshots and CMS revision restore stay independent from draft edits", %{
    scope: scope
  } do
    {:ok, article} = Blog.create(scope, "stable-address")
    assert Blog.published() == []
    assert {:error, :invalid_content} = Blog.publish(scope, article)
    {:ok, article} = Blog.save(scope, article, payload())
    {:ok, article} = Blog.publish(scope, article)
    published = Blog.published(article.slug)
    assert published.payload == payload()
    changed = put_in(payload(), ["en", "summary"], "Changed draft")
    {:ok, changed_article} = Blog.save(scope, article, changed)
    assert Blog.published(article.slug) == published
    assert {:error, :stale} = Blog.save(scope, article, payload())
    {:ok, history} = Blog.history(scope, changed_article)
    revision = Enum.find(history, &(&1.action == "created"))
    {:ok, restored} = Blog.restore(scope, changed_article, revision.id)
    assert restored.payload == Blog.empty_payload()
    assert Blog.published(article.slug) == published
    {:ok, unpublished} = Blog.unpublish(scope, restored)
    assert Blog.published(article.slug) == nil
    {:ok, archived} = Blog.archive(scope, unpublished)
    assert archived.archived_at
    assert {:ok, []} = Blog.list(scope)
    assert {:ok, revisions} = Blog.history(scope, archived)
    assert length(revisions) == 7
  end

  test "one complete edition can publish without exposing an unfinished translation", %{
    scope: scope
  } do
    {:ok, article} = Blog.create(scope, "english-first")
    payload = Blog.empty_payload() |> Map.put("en", payload()["en"])
    {:ok, article} = Blog.save(scope, article, payload)
    {:ok, article} = Blog.publish(scope, article)
    assert Blog.published(article.slug).payload == Map.take(payload, ["en"])
    assert article.payload["fr"] == Blog.empty_payload()["fr"]
  end

  test "fresh role revocation and malformed inputs cannot mutate articles", %{
    scope: scope,
    user: user
  } do
    assert {:error, _} = Blog.create(scope, "../unsafe")
    {:ok, article} = Blog.create(scope, "one-address")
    assert {:error, _} = Blog.create(scope, "one-address")
    assert {:error, :invalid_content} = Blog.save(scope, article, %{"en" => %{}})
    Repo.update!(Ecto.Changeset.change(user, superadmin: false))
    assert {:error, :unauthorized} = Blog.save(scope, article, payload())
    assert {:error, :unauthorized} = Blog.publish(scope, article)
    assert {:error, :unauthorized} = Blog.archive(scope, article)
    assert Blog.published() == []
  end
end
