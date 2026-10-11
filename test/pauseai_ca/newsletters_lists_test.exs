defmodule PauseAiCa.NewslettersListsTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters}
  alias PauseAiCa.Newsletters.{Lists, Drafts, Batches, Batch, Delivery, Subscription}

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    flush_emails()
    %{scope: Accounts.Scope.for_user(admin), admin: admin}
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp signup(email, attrs, confirmed \\ true) do
    {:ok, request} = Newsletters.request_signup(email, Map.merge(%{consent: true}, attrs))
    if confirmed, do: Newsletters.confirm(request.confirmation_token)
    Repo.get_by!(Subscription, email: email)
  end

  defp list(scope, mode \\ "any") do
    {:ok, list} =
      Lists.save(scope, nil, %{
        "name" => "Montréal + H2X",
        "match" => mode,
        "city" => "Montréal",
        "region" => "",
        "fsas" => "h2x"
      })

    list
  end

  test "OR/AND membership is dynamic, unknown geography stays out and consent exclusions remain visible",
       c do
    list = list(c.scope)
    signup("city@example.org", %{city: "Montreal"})
    fsa = signup("postal@example.org", %{city: "Laval", fsa: "H2X"})
    signup("unknown@example.org", %{})
    signup("pending@example.org", %{fsa: "H2X"}, false)
    {:ok, page} = Newsletters.audience_page(c.scope, %{"list_id" => list.id})
    assert page.total == 3
    assert page.counts.included == 2
    assert page.counts.unconfirmed == 1
    assert Enum.find(page.rows, &(&1.subscription.id == fsa.id)).matched_fields == ["fsa"]
    fsa |> change(fsa: "J4B") |> Repo.update!()
    {:ok, next} = Newsletters.audience_page(c.scope, %{"list_id" => list.id})
    assert next.total == 2

    {:ok, both} =
      Lists.save(c.scope, list, %{
        "name" => list.name,
        "match" => "all",
        "city" => "Montréal",
        "fsas" => "H2X"
      })

    assert {:ok, %{total: 0}} = Newsletters.audience_page(c.scope, %{"list_id" => both.id})
  end

  test "whole-list batches span pagination, snapshot exact recipients and become stale on rule or membership change",
       c do
    list = list(c.scope)
    for n <- 1..27, do: signup("member-#{n}@example.org", %{fsa: "H2X"})
    signup("not-in-list@example.org", %{fsa: "J4B"})
    signup("not-confirmed@example.org", %{fsa: "H2X"}, false)
    {:ok, draft} = Drafts.create(c.scope)

    {:ok, draft} =
      Drafts.save(c.scope, draft, %{
        "subject" => "Local news",
        "source" => "Montréal news",
        "recipient_mode" => "list",
        "mailing_list_id" => list.id
      })

    before_accounts = Repo.aggregate(Accounts.User, :count)
    {:ok, batch} = Batches.prepare(c.scope, draft, "list", [], false)
    assert length(batch.recipient_keys) == 27
    assert Repo.aggregate(Delivery, :count) == 27
    assert batch.mailing_list_revision == list.revision
    {:ok, _} = Batches.approve(c.scope, batch.id)
    signup("new-match@example.org", %{fsa: "H2X"})
    assert {:ok, :stale} = Batches.dispatch(c.scope, batch.id)
    refute_receive {:email, _}
    assert Repo.aggregate(Accounts.User, :count) == before_accounts
    {:ok, next} = Batches.prepare(c.scope, draft, "list", [], false)
    assert length(next.recipient_keys) == 28
    {:ok, _} = Batches.approve(c.scope, next.id)

    {:ok, _} =
      Lists.save(c.scope, list, %{"name" => "Renamed", "match" => "any", "fsas" => "H2X"})

    assert {:ok, :stale} = Batches.dispatch(c.scope, next.id)
    refute_receive {:email, _}
    assert Repo.aggregate(Batch, :count) == 2
  end

  test "a fresh whole-list approval delivers only confirmed matching addresses and deduplicates preparation",
       c do
    list = list(c.scope)
    signup("in-list@example.org", %{fsa: "H2X"})
    signup("pending-list@example.org", %{fsa: "H2X"}, false)
    signup("outside-list@example.org", %{fsa: "J4B"})
    {:ok, draft} = Drafts.create(c.scope)

    {:ok, draft} =
      Drafts.save(c.scope, draft, %{
        "subject" => "Local news",
        "source" => "Local newsletter",
        "recipient_mode" => "list",
        "mailing_list_id" => list.id
      })

    {:ok, batch} = Batches.prepare(c.scope, draft, "list", [], false)
    {:ok, same} = Batches.prepare(c.scope, draft, "list", [], false)
    assert same.id == batch.id
    assert {:ok, :not_approved} = Batches.dispatch(c.scope, batch.id)
    refute_receive {:email, _}
    assert {:ok, _} = Batches.approve(c.scope, batch.id)
    assert {:ok, :completed} = Batches.dispatch(c.scope, batch.id)
    assert_receive {:email, message}
    assert message.to == [{"", "in-list@example.org"}]
    assert message.html_body =~ "Unsubscribe"
    refute_receive {:email, _}
    assert Repo.aggregate(Delivery, :count) == 1
  end

  test "existing newsletter preparation fingerprints stay compatible with0.5.12", c do
    previous_env = Application.fetch_env!(:pauseai_ca, :mail_environment)
    on_exit(fn -> Application.put_env(:pauseai_ca, :mail_environment, previous_env) end)
    Application.put_env(:pauseai_ca, :mail_environment, :dev)

    sub =
      Repo.insert!(%Subscription{
        id: "00000000-0000-4000-8000-000000000002",
        email: "legacy-reader@example.org",
        state: "confirmed",
        confirmed_at: DateTime.utc_now(),
        consent_version: "synthetic-legacy-consent"
      })

    draft =
      Repo.insert!(%Newsletters.Draft{
        id: "00000000-0000-4000-8000-000000000001",
        owner_id: c.admin.id,
        subject: "Legacy fixture",
        source: "Legacy newsletter"
      })

    {:ok, batch} = Batches.prepare(c.scope, draft, "newsletter", [sub.id], false)
    # Golden fingerprint from the0.5.12 format for this fixed synthetic fixture.
    assert Base.encode16(batch.preparation_key, case: :lower) ==
             "005e5b8cbe9cea7ef0dd351da97f61e621586422842a07cc3269c4d4af3eb00d"

    {:ok, repeated} = Batches.prepare(c.scope, draft, "newsletter", [sub.id], false)
    assert repeated.id == batch.id
    assert Repo.aggregate(Delivery, :count) == 1
    refute_receive {:email, _}
  end

  test "invalid FSA and stale/revoked edits preserve definitions and cannot authorize sending",
       c do
    list = list(c.scope)

    assert {:error, :invalid_rules} =
             Lists.save(c.scope, list, %{"name" => "Bad", "fsas" => "ABC"})

    {:ok, saved} = Lists.save(c.scope, list, %{"name" => "New name", "city" => "Montréal"})

    assert {:error, :stale} =
             Lists.save(c.scope, list, %{"name" => "Stale", "city" => "Montréal"})

    c.admin |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Lists.get(c.scope, saved.id)
    assert {:error, :unauthorized} = Lists.archive(c.scope, saved)
    assert Repo.aggregate(Delivery, :count) == 0
  end
end
