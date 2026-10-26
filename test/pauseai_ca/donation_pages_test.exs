defmodule PauseAiCa.DonationPagesTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts.{Scope, User, UserToken}
  alias PauseAiCa.Donations.{Pages, Page, PageRevision}

  setup do
    user = user_fixture() |> change(superadmin: true) |> Repo.update!()
    %{scope: Scope.for_user(user)}
  end

  test "public fallback is read-only and management authority is freshly confirmed", c do
    assert Pages.published() == nil
    assert Pages.published() == nil
    assert Repo.aggregate(Page, :count) == 0
    ordinary = user_fixture() |> Scope.for_user()

    for scope <- [nil, ordinary] do
      assert {:error, :unauthorized} = Pages.get_or_create(scope)
      assert {:error, :unauthorized} = Pages.history(scope)
      assert {:error, :unauthorized} = Pages.preview(scope, Pages.defaults())
    end

    assert {:ok, page} = Pages.get_or_create(c.scope)
    c.scope.user |> change(superadmin: false) |> Repo.update!()

    for result <- [
          Pages.get_or_create(c.scope),
          Pages.save(c.scope, page, Pages.defaults()),
          Pages.publish(c.scope, page),
          Pages.history(c.scope),
          Pages.restore(c.scope, page, Ecto.UUID.generate()),
          Pages.preview(c.scope, Pages.defaults())
        ] do
      assert result == {:error, :unauthorized}
    end

    assert Repo.aggregate(PageRevision, :count) == 1
  end

  test "drafts, explicit publication, history and restore remain distinct attributed CMS revisions",
       c do
    assert {:ok, initial} = Pages.get_or_create(c.scope)
    assert initial.revision == 1
    assert Pages.published() == nil
    revised = put_in(initial.payload, ["editions", "en", "lead"], "Revised local campaign copy")
    assert {:ok, draft} = Pages.save(c.scope, initial, revised)
    assert Pages.published() == nil
    assert {:ok, published} = Pages.publish(c.scope, draft)
    assert published.published_revision == published.revision
    assert Pages.published() == revised

    assert {:ok, later} =
             Pages.save(
               c.scope,
               published,
               put_in(revised, ["editions", "fr", "title"], "Un titre en préparation")
             )

    assert Pages.published() == revised
    assert {:ok, entries} = Pages.history(c.scope)
    assert Enum.map(entries, & &1.action) == ["saved", "published", "saved", "created"]
    assert Enum.all?(entries, &(&1.editor_id == c.scope.user.id))
    original = Enum.find(entries, &(&1.action == "created"))
    assert {:ok, restored} = Pages.restore(c.scope, later, original.id)
    assert restored.payload == initial.payload
    assert restored.revision == later.revision + 1
    assert restored.published_payload == revised and Pages.published() == revised
    assert {:ok, [latest | unchanged]} = Pages.history(c.scope)
    assert latest.action == "restored" and latest.payload == initial.payload
    assert unchanged == entries
  end

  test "stale editor operations cannot overwrite, publish or restore another revision", c do
    {:ok, first} = Pages.get_or_create(c.scope)

    {:ok, second} =
      Pages.save(
        c.scope,
        first,
        put_in(first.payload, ["editions", "en", "title"], "Fresh draft")
      )

    assert {:error, :stale} = Pages.save(c.scope, first, first.payload)
    assert {:error, :stale} = Pages.publish(c.scope, first)
    assert {:error, :stale} = Pages.restore(c.scope, first, Ecto.UUID.generate())
    assert {:error, :not_found} = Pages.restore(c.scope, second, Ecto.UUID.generate())
    assert Repo.get!(Page, first.id).payload == second.payload
    assert Repo.aggregate(PageRevision, :count) == 2
    assert Pages.published() == nil
  end

  test "draft copy may be incomplete but publication requires both editions and a complete scenario",
       c do
    {:ok, page} = Pages.get_or_create(c.scope)

    incomplete =
      page.payload
      |> put_in(["editions", "fr", "lead"], "")
      |> put_in(["stages", Access.at(0), "buckets", Access.at(0), "label_en"], "")

    assert {:ok, draft} = Pages.save(c.scope, page, incomplete)
    assert {:error, %Ecto.Changeset{valid?: false}} = Pages.publish(c.scope, draft)
    assert Repo.aggregate(PageRevision, :count) == 2
    assert Pages.published() == nil
    assert {:ok, _} = Pages.preview(c.scope, incomplete)
    mismatch = put_in(page.payload, ["stages", Access.at(0), "target_minor"], 1_400_001)
    assert {:ok, draft2} = Pages.save(c.scope, draft, mismatch)
    assert {:error, %Ecto.Changeset{}} = Pages.publish(c.scope, draft2)
  end

  test "unsafe links, malformed money, provider totals and ambiguous stage identities are rejected",
       c do
    {:ok, page} = Pages.get_or_create(c.scope)
    original = page.payload

    invalid = [
      put_in(original, ["currency"], "USD"),
      put_in(original, ["links", "campaign"], "javascript:alert(1)"),
      put_in(original, ["links", "campaign"], "https://example.org/projects/example"),
      put_in(
        original,
        ["links", "campaign"],
        "https://manifund.org.example.org/projects/example"
      ),
      put_in(
        original,
        ["links", "campaign"],
        "https://manifund.org@evil.example/projects/example"
      ),
      put_in(original, ["links", "campaign"], "https://manifund.org/projects/example?redirect=1"),
      put_in(original, ["links", "campaign"], "https://manifund.org/projects/example#section"),
      put_in(original, ["links", "campaign"], "https://manifund.org:444/projects/example"),
      put_in(original, ["links", "brochure"], "https://user:password@example.org/book"),
      put_in(original, ["links", "campaign"], "https://example.org/\nmalformed"),
      put_in(original, ["stages", Access.at(0), "buckets", Access.at(0), "amount_minor"], 1.1),
      put_in(original, ["stages", Access.at(0), "buckets", Access.at(0), "amount_minor"], 0),
      put_in(original, ["stages", Access.at(1), "target_minor"], 100),
      put_in(original, ["stages", Access.at(1), "id"], hd(original["stages"])["id"]),
      Map.put(original, "received_minor", 999_999),
      Map.put(original, "fx_rate", 1.4)
    ]

    for payload <- invalid do
      assert {:error, %Ecto.Changeset{valid?: false}} = Pages.save(c.scope, page, payload)
    end

    assert Repo.get!(Page, page.id).payload == original
    assert Repo.aggregate(PageRevision, :count) == 1
  end

  test "default stages preserve complete CAD scenarios and configured tie order", c do
    {:ok, page} = Pages.get_or_create(c.scope)
    stages = page.payload["stages"]

    assert Enum.map(stages, & &1["target_minor"]) == [
             1_400_000,
             3_800_000,
             31_500_000,
             159_500_000
           ]

    assert Enum.sum(Enum.map(stages, &length(&1["buckets"]))) == 65

    for stage <- stages do
      assert Enum.sum(Enum.map(stage["buckets"], & &1["amount_minor"])) == stage["target_minor"]
    end

    assert {:ok, published} = Pages.publish(c.scope, page)
    assert published.published_payload["stages"] == stages

    assert published.published_payload["display"] == %{
             "mode" => "remaining_after_threshold",
             "remaining_threshold_percent" => 50,
             "show_remaining_above" => true
           }
  end

  test "concurrent singleton creation commits exactly one row and one attributed revision" do
    scope =
      unboxed(fn ->
        user_fixture() |> change(superadmin: true) |> Repo.update!() |> Scope.for_user()
      end)

    try do
      assert unboxed(fn -> Repo.aggregate(Page, :count) end) == 0
      parent = self()

      jobs =
        for _ <- 1..2 do
          Task.async(fn ->
            send(parent, {:ready, self()})

            receive do
              :go -> unboxed(fn -> Pages.get_or_create(scope) end)
            end
          end)
        end

      for _ <- jobs do
        assert_receive {:ready, pid}
        send(pid, :go)
      end

      results = Enum.map(jobs, &Task.await(&1, 10_000))
      assert [{:ok, a}, {:ok, b}] = results
      assert a.id == b.id and a.revision == 1 and b.revision == 1
      assert unboxed(fn -> Repo.aggregate(Page, :count) end) == 1
      assert unboxed(fn -> Repo.aggregate(PageRevision, :count) end) == 1
    after
      unboxed(fn ->
        page_ids = from(p in Page, where: p.updated_by == ^scope.user.id, select: p.id)
        Repo.delete_all(from r in PageRevision, where: r.page_id in subquery(page_ids))
        Repo.delete_all(from p in Page, where: p.updated_by == ^scope.user.id)
        Repo.delete_all(from t in UserToken, where: t.user_id == ^scope.user.id)
        Repo.delete_all(from u in User, where: u.id == ^scope.user.id)
      end)
    end
  end

  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
end
