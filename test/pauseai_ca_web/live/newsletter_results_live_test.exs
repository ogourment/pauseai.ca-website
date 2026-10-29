defmodule PauseAiCaWeb.NewsletterResultsLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters, Repo}
  alias PauseAiCa.Newsletters.{Batch, Batches, Delivery, Drafts, ResultSnapshot, Results}

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    {:ok, signup} = Newsletters.request_signup("overview@example.org", %{consent: true})
    {:ok, _} = Newsletters.confirm(signup.confirmation_token)
    {:ok, draft} = Drafts.create(scope)

    {:ok, draft} =
      Drafts.save(scope, draft, %{
        "subject" => "One newsletter, two sends",
        "source" =>
          "# Saved issue\n\n[Story](https://example.org/story)\n\n<script>alert(1)</script>",
        "recipient_mode" => "newsletter",
        "recipient_keys" => [signup.subscription.id]
      })

    {:ok, batch} = Batches.prepare(scope, draft, "newsletter", [signup.subscription.id], true)
    delivery = Repo.get_by!(Delivery, batch_id: batch.id)

    delivery
    |> Ecto.Changeset.change(
      state: "accepted",
      attempted_at: DateTime.utc_now(),
      authorizing_admin_id: admin.id
    )
    |> Repo.update!()

    %{conn: log_in_user(conn, admin), scope: scope, batch: batch, delivery: delivery}
  end

  test "stored summaries distinguish missing, partial and empty observations and retain authority",
       c do
    assert Results.overview(c.scope, [c.batch.id])[c.batch.id].provider == nil
    at = DateTime.add(DateTime.utc_now(), -3600)

    Repo.insert!(%ResultSnapshot{
      batch_id: c.batch.id,
      observed: %{"delivered" => 1, "clicked" => 1},
      partial: true,
      refreshed_at: at
    })

    summary = Results.overview(c.scope, [c.batch.id])[c.batch.id]
    assert summary.states == %{"accepted" => 1}
    assert summary.provider.partial
    assert summary.provider.refreshed_at == at
    c.scope.user |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert Results.overview(c.scope, [c.batch.id]) == %{}
    assert {:error, :unauthorized} = Results.list_context(c.scope, [c.batch.id])
  end

  test "compact rows expose cached outcomes and saved content with stable next/back context", c do
    second = clone_batch(c, DateTime.add(c.batch.inserted_at, -10))

    Repo.insert!(%ResultSnapshot{
      batch_id: c.batch.id,
      observed: %{"delivered" => 1, "opened" => 1, "clicked" => 1},
      partial: false,
      refreshed_at: DateTime.utc_now()
    })

    {:ok, view, html} = live(c.conn, "/manage/mail/results?locale=en")
    assert has_element?(view, "#send-#{c.batch.id} [data-stored-results]", "Observed clicks")
    assert has_element?(view, "#send-#{second.id}", "Unavailable results are not zero")
    assert html =~ "One newsletter, two sends"
    assert has_element?(view, "#provider-synchronization:not([open])")
    assert has_element?(view, "#send-#{c.batch.id}", "Planned recipients: 1")
    view |> element("#send-#{c.batch.id} a") |> render_click()
    assert has_element?(view, "#sent-content-preview iframe[sandbox='']")

    srcdoc =
      view
      |> element("#sent-content-preview iframe")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("iframe")
      |> LazyHTML.attribute("srcdoc")
      |> hd()

    assert srcdoc =~ "<h1>Saved issue</h1>"
    refute srcdoc =~ "<a "
    refute srcdoc =~ "<script>"
    assert srcdoc =~ "default-src 'none'"
    assert render(view) =~ "No saved link-level report is available"
    newer = clone_batch(c, DateTime.add(c.batch.inserted_at, 10))
    view |> element("nav a", "Next send") |> render_click()
    assert has_element?(view, "nav a", "Previous send")
    view |> element("nav a", "Back to results") |> render_click()
    assert has_element?(view, "#send-#{c.batch.id}")
    assert has_element?(view, "#send-#{second.id}")
    refute has_element?(view, "#send-#{newer.id}")
  end

  test "manual email rows keep recipient identity visible without opening details", c do
    manual = clone_batch(c, DateTime.add(c.batch.inserted_at, -10))
    manual |> Ecto.Changeset.change(recipient_mode: "contacts") |> Repo.update!()
    {:ok, view, _} = live(c.conn, "/manage/mail/results?locale=en")

    assert has_element?(
             view,
             "#send-#{manual.id} [data-manual-recipients]",
             "overview@example.org"
           )

    assert has_element?(view, "#send-#{manual.id} details:not([open])")
  end

  test "cached zero observations are explicitly inconclusive", c do
    Repo.insert!(%ResultSnapshot{
      batch_id: c.batch.id,
      observed: %{"delivered" => 0, "clicked" => 0},
      partial: false,
      refreshed_at: DateTime.utc_now()
    })

    {:ok, view, _} = live(c.conn, "/manage/mail/results?locale=en")

    assert has_element?(
             view,
             "#send-#{c.batch.id}",
             "No deliveries, opens or clicks reported yet"
           )
  end

  test "saved link aggregates are shown beside the inert content preview", c do
    Repo.insert!(%ResultSnapshot{
      batch_id: c.batch.id,
      observed: %{
        "clicked" => 1,
        "links" => %{
          "version" => 1,
          "complete" => true,
          "items" => [%{"url" => "https://example.org/story", "label" => "Story", "clicked" => 1}]
        }
      },
      partial: false,
      refreshed_at: DateTime.utc_now()
    })

    {:ok, view, _} = live(c.conn, "/manage/mail/results/#{c.batch.id}?locale=en")
    assert has_element?(view, "#clicked-links", "Story")
    assert has_element?(view, "#clicked-links strong", "1")
    refute has_element?(view, "#clicked-links a")
    refute render(view) =~ "No saved link-level report is available"
  end

  defp clone_batch(c, at) do
    attrs =
      c.batch
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id])
      |> Map.put(:inserted_at, at)
      |> Map.put(:preparation_key, :crypto.strong_rand_bytes(32))

    batch = Repo.insert!(struct(Batch, attrs))

    attrs =
      c.delivery
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id])
      |> Map.merge(%{
        batch_id: batch.id,
        state: "accepted",
        attempted_at: at,
        authorizing_admin_id: c.scope.user.id
      })

    Repo.insert!(struct(Delivery, attrs))
    batch
  end
end
