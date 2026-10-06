defmodule PauseAiCa.NewslettersBatchesTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters}
  alias PauseAiCa.Newsletters.{Batches, Drafts, Delivery, Batch}

  setup do
    actor = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(actor)
    {:ok, draft} = Drafts.create(scope)

    {:ok, draft} =
      Drafts.save(scope, draft, %{
        "subject" => "Protest press release",
        "source" => "# Montréal\n\nA reviewed press release."
      })

    previous = Application.fetch_env!(:pauseai_ca, :mail_environment)
    on_exit(fn -> Application.put_env(:pauseai_ca, :mail_environment, previous) end)
    flush_emails()
    %{actor: actor, scope: scope, draft: draft}
  end

  test "fourteen manually reviewed contacts prepare once, require approval and deliver once without accounts or newsletter consent",
       c do
    contacts = contacts(14)
    ids = Enum.map(contacts, & &1.id)
    accounts = Repo.aggregate(Accounts.User, :count)
    assert {:error, :review_required} = Batches.prepare(c.scope, c.draft, "contacts", ids, false)
    assert Repo.aggregate(Batch, :count) == 0
    assert {:ok, batch} = Batches.prepare(c.scope, c.draft, "contacts", ids, true)
    assert {:ok, same} = Batches.prepare(c.scope, c.draft, "contacts", ids, true)
    assert same.id == batch.id
    assert Repo.aggregate(Delivery, :count) == 14
    assert Repo.aggregate(Batch, :count) == 1
    assert {:ok, :not_approved} = Batches.dispatch(c.scope, batch.id)
    refute_receive {:email, _}
    assert {:ok, _} = Batches.approve(c.scope, batch.id)
    assert {:ok, :completed} = Batches.dispatch(c.scope, batch.id)

    delivered =
      for _ <- 1..14 do
        assert_receive {:email, email}
        assert email.cc == [] and email.bcc == []
        assert email.html_body =~ "Manage my subscription"
        assert email.html_body =~ "<h1>Montréal</h1>"
        assert email.text_body =~ "A reviewed press release."
        email
      end

    assert Enum.uniq_by(delivered, & &1.to) == delivered
    assert {:ok, :not_approved} = Batches.dispatch(c.scope, batch.id)
    refute_receive {:email, _}

    assert Enum.all?(
             Repo.all(Delivery),
             &(&1.state == "accepted" and &1.authorizing_admin_id == c.actor.id)
           )

    assert Repo.aggregate(Accounts.User, :count) == accounts

    assert Enum.all?(
             Repo.all(Newsletters.Subscription),
             &(&1.state == "outreach_only" and is_nil(&1.confirmed_at) and
                 is_nil(&1.consent_version))
           )
  end

  test "draft changes and opt-outs invalidate approval before any send", c do
    [contact] = contacts(1)
    {:ok, batch} = Batches.prepare(c.scope, c.draft, "contacts", [contact.id], true)
    {:ok, _} = Batches.approve(c.scope, batch.id)
    {:ok, changed} = Drafts.save(c.scope, c.draft, %{"subject" => "Changed after approval"})
    assert {:ok, :stale} = Batches.dispatch(c.scope, batch.id)
    refute_receive {:email, _}
    {:ok, next} = Batches.prepare(c.scope, changed, "contacts", [contact.id], true)
    {:ok, _} = Batches.approve(c.scope, next.id)
    [delivery] = Repo.all(from d in Delivery, where: d.batch_id == ^next.id)

    {:ok, raw} =
      Phoenix.Token.decrypt(
        PauseAiCaWeb.Endpoint,
        "newsletter delivery footer",
        delivery.withdrawal_token,
        max_age: :infinity
      )

    {:ok, _} = Newsletters.withdraw(raw)
    assert {:ok, :stale} = Batches.dispatch(c.scope, next.id)
    refute_receive {:email, _}
    refute Newsletters.outreach_eligible?(delivery.email)
  end

  test "durable per-admin reservations throttle after twenty, including batches subsequently paused",
       c do
    keys = contacts(25) |> Enum.map(& &1.id)
    {:ok, batch} = Batches.prepare(c.scope, c.draft, "contacts", keys, true)
    {:ok, _} = Batches.approve(c.scope, batch.id)
    assert {:ok, :throttled} = Batches.dispatch(c.scope, batch.id)
    assert Repo.aggregate(from(d in Delivery, where: d.state == "accepted"), :count) == 20
    assert Repo.aggregate(from(d in Delivery, where: d.state == "pending"), :count) == 5
    {:ok, _} = Batches.pause(c.scope, batch.id)
    {:ok, newer} = Drafts.save(c.scope, c.draft, %{"subject" => "Another reviewed version"})
    {:ok, next} = Batches.prepare(c.scope, newer, "contacts", keys, true)
    {:ok, _} = Batches.approve(c.scope, next.id)
    assert {:ok, :throttled} = Batches.dispatch(c.scope, next.id)
    assert Repo.aggregate(from(d in Delivery, where: not is_nil(d.attempted_at)), :count) == 20
  end

  test "staging redirects each recipient to the current authorizing admin; revoked actors cannot dispatch",
       c do
    Application.put_env(:pauseai_ca, :mail_environment, :staging)
    keys = contacts(5) |> Enum.map(& &1.id)
    {:ok, batch} = Batches.prepare(c.scope, c.draft, "contacts", keys, true)
    {:ok, _} = Batches.approve(c.scope, batch.id)
    assert {:ok, :completed} = Batches.dispatch(c.scope, batch.id)

    for _ <- 1..5 do
      assert_receive {:email, email}
      assert email.to == [{"Staging admin", c.actor.email}]
      assert String.starts_with?(email.subject, "[STAGING]")
    end

    c.actor |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Batches.dispatch(c.scope, batch.id)
    assert {:error, :unauthorized} = Batches.get(c.scope, batch.id)
  end

  test "global rolling quota holds at one hundred across authorizers", c do
    keys = contacts(100) |> Enum.map(& &1.id)
    other = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(other)
    flush_emails()
    {:ok, draft} = Drafts.create(scope)

    {:ok, draft} =
      Drafts.save(scope, draft, %{"subject" => "Other operator", "source" => "A reviewed message"})

    {:ok, batch} = Batches.prepare(scope, draft, "contacts", keys, true)
    {:ok, _} = Batches.approve(scope, batch.id)

    Repo.update_all(from(d in Delivery, where: d.batch_id == ^batch.id),
      set: [state: "accepted", attempted_at: DateTime.utc_now(), authorizing_admin_id: other.id]
    )

    {:ok, mine} = Batches.prepare(c.scope, c.draft, "contacts", [hd(keys)], true)
    {:ok, _} = Batches.approve(c.scope, mine.id)
    assert {:ok, :throttled} = Batches.dispatch(c.scope, mine.id)
    assert {:ok, %{personal_remaining: 20, global_remaining: 0}} = Batches.quota(c.scope)
    refute_receive {:email, _}
  end

  test "a live reservation blocks a second dispatcher; interrupted submissions require reconciliation",
       c do
    [person] = contacts(1)
    {:ok, batch} = Batches.prepare(c.scope, c.draft, "contacts", [person.id], true)
    {:ok, _} = Batches.approve(c.scope, batch.id)
    delivery = Repo.one!(Delivery)

    delivery
    |> change(
      state: "reserved",
      authorizing_admin_id: c.actor.id,
      attempted_at: DateTime.utc_now()
    )
    |> Repo.update!()

    assert {:ok, :already_sending} = Batches.dispatch(c.scope, batch.id)
    refute_receive {:email, _}

    delivery
    |> change(
      state: "reserved",
      authorizing_admin_id: c.actor.id,
      attempted_at: DateTime.add(DateTime.utc_now(), -301)
    )
    |> Repo.update!()

    assert {:ok, :reconciliation_required} = Batches.dispatch(c.scope, batch.id)
    assert Repo.get!(Delivery, delivery.id).state == "unknown"
    assert {:error, :reconciliation_required} = Batches.approve(c.scope, batch.id)
    refute_receive {:email, _}
  end

  defp contacts(n) do
    for i <- 1..n do
      person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic protest contact #{i}"})
      Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: "press-#{i}@example.org"})
      person
    end
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
