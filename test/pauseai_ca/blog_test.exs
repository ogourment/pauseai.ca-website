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
         "markdown" =>
           "# Title #{locale}\n\nShort #{locale}\n\n## Detail #{locale}\n\nDetails #{locale}\n\n### Complete #{locale}\n\nComplete #{locale}"
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
    changed = put_in(payload(), ["en", "markdown"], "# Changed draft\n\nNew introduction")
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

  test "legacy snapshots survive edit, Markdown publication and restoring the exact old revision",
       %{scope: scope} do
    legacy =
      Map.new(~w(en fr), fn locale ->
        {locale,
         %{
           "title" => "Old #{locale}",
           "summary" => "Original intro #{locale}",
           "details" => "## Existing heading\n\nDetailed original.",
           "full" => "Full original.\n"
         }}
      end)

    {:ok, article} = Blog.create(scope, "legacy-history")
    {:ok, article} = Blog.save(scope, article, legacy)
    {:ok, article} = Blog.publish(scope, article)
    {:ok, before} = Blog.history(scope, article)
    original_revision = Enum.find(before, &(&1.action == "published"))
    converted = PauseAiCa.Blog.Markdown.payload(legacy)
    {:ok, article} = Blog.save(scope, article, converted)
    assert Blog.published(article.slug).payload == legacy
    {:ok, article} = Blog.publish(scope, article)
    assert Blog.published(article.slug).payload == converted
    {:ok, restored} = Blog.restore(scope, article, original_revision.id)
    assert restored.payload == legacy
    assert Blog.published(article.slug).payload == converted
    {:ok, after_history} = Blog.history(scope, restored)
    assert Enum.find(after_history, &(&1.id == original_revision.id)) == original_revision
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
