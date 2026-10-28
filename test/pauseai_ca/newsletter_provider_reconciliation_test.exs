defmodule PauseAiCa.NewsletterProviderReconciliationTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters, MailSafety}

  alias PauseAiCa.Newsletters.{
    Batches,
    ConsentEvent,
    Delivery,
    Drafts,
    ProviderEvent,
    ProviderReconciliation,
    ProviderSync,
    ProviderHistory,
    ProviderSyncWorker,
    Subscription
  }

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    assert_receive {:email, _}
    scope = Accounts.Scope.for_user(admin)
    fixture = receipt(scope, "recipient@example.org", "exact-message")
    Map.merge(fixture, %{scope: scope})
  end

  test "read-only preview, exact frozen identities, idempotence and permanent address-only failure",
       c do
    person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic"})
    Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: c.subscription.email})
    alternate = subscribe("alias@example.org")
    Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: alternate.email})
    hard = event(c, "hardBounces")

    events = [
      hard,
      hard,
      Map.put(hard, "messageId", "not-the-message"),
      Map.put(hard, "email", "someone-else@example.org")
    ]

    assert {:ok, preview} = ProviderReconciliation.preview(events)
    assert preview["hard_bounce"] == 1
    assert preview["unmatched"] == 2
    assert preview["duplicates"] == 1
    assert Repo.aggregate(ProviderEvent, :count) == 0
    assert Newsletters.eligible?(c.subscription.email)
    assert {:ok, ^preview} = ProviderReconciliation.reconcile(events)
    assert {:ok, replay} = ProviderReconciliation.reconcile(events)
    assert replay["new_events"] == 0
    assert replay["already_recorded"] == 1
    assert Repo.aggregate(ProviderEvent, :count) == 1
    assert Repo.get!(Subscription, c.subscription.id).state == "confirmed"
    refute Newsletters.eligible?(c.subscription.email)
    assert Newsletters.eligible?(alternate.email)

    assert {:ok, _} =
             ProviderReconciliation.reconcile([event(c, "delivered"), event(c, "opened")])

    assert PauseAiCa.Mail.suppressed?(c.subscription.email)
    refute PauseAiCa.Mail.suppressed?(alternate.email)
    assert {:ok, audience} = Newsletters.audience_page(c.scope, %{})
    assert audience.counts.hard_bounce == 1
    assert audience.counts.included == 1
  end

  test "provider withdrawal retains original time, blocks aliases and never duplicates existing withdrawal",
       c do
    person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic"})
    Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: c.subscription.email})
    alternate = subscribe("alias@example.org")
    Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: alternate.email})
    provider = event(c, "unsubscribed")
    {:ok, at, _} = DateTime.from_iso8601(provider["date"])
    assert {:ok, %{"unsubscribe" => 1}} = ProviderReconciliation.reconcile([provider])
    assert Repo.get!(Subscription, c.subscription.id).withdrawn_at == at
    refute Newsletters.eligible?(alternate.email)
    # Purpose withdrawal leaves ordinary individual-mail deliverability separate.
    refute PauseAiCa.Mail.suppressed?(alternate.email)
    assert Repo.aggregate(from(e in ConsentEvent, where: e.kind == "withdrawn"), :count) == 1

    assert {:ok, _} =
             ProviderReconciliation.reconcile([Map.put(provider, "id", "another-observation")])

    assert Repo.aggregate(from(e in ConsentEvent, where: e.kind == "withdrawn"), :count) == 1
    assert Repo.get!(Subscription, c.subscription.id).withdrawn_at == at
    assert {:ok, result} = PauseAiCa.Newsletters.Results.get(c.scope, c.batch.id)
    assert result.local_unsubscribed == 1
  end

  test "an old provider withdrawal preserves a later explicit choice and exposes the unresolved conflict",
       c do
    old =
      event(c, "unsubscribed")
      |> Map.put("date", DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -86_400)))

    assert {:ok, %{"consent_conflicts" => 1, "new_withdrawals" => 0}} =
             ProviderReconciliation.preview([old])

    assert {:ok, _} = ProviderReconciliation.reconcile([old])
    assert Repo.get!(Subscription, c.subscription.id).state == "confirmed"
    assert Repo.one!(ProviderEvent).consent_conflict
    refute Newsletters.eligible?(c.subscription.email)
    assert {:ok, result} = PauseAiCa.Newsletters.Results.get(c.scope, c.batch.id)
    assert result.reconciliation["conflicts"] == 1
    assert result.local_unsubscribed == 0
  end

  test "soft bounces flag review, invalid DNS holds only that address, sender reputation does not penalize recipients",
       c do
    full = receipt(c.scope, "full@example.org", "full-message")
    sender = receipt(c.scope, "sender@example.org", "sender-message")

    rows = [
      event(c, "softBounces", "Unable to find MX for domain"),
      event(full, "softBounces", "Mailbox full"),
      event(sender, "softBounces", "Sender IP on Spamhaus RBL")
    ]

    assert {:ok, %{"review" => 3, "invalid_domain" => 1}} = ProviderReconciliation.reconcile(rows)
    refute Newsletters.eligible?(c.subscription.email)
    assert Newsletters.eligible?(full.subscription.email)
    assert Newsletters.eligible?(sender.subscription.email)
    assert Repo.get!(Subscription, c.subscription.id).state == "confirmed"
    assert {:ok, audience} = Newsletters.audience_page(c.scope, %{})
    assert audience.counts.invalid_domain == 1
    assert audience.counts.included == 2
  end

  test "fresh single/authentication and approved-batch boundaries exclude an address that subsequently hard bounces",
       c do
    pending = pending_batch(c.scope, c.subscription)
    assert {:ok, _} = Batches.approve(c.scope, pending.id)
    assert {:ok, _} = ProviderReconciliation.reconcile([event(c, "hardBounces")])
    assert {:ok, :stale} = Batches.dispatch(c.scope, pending.id)

    message =
      Swoosh.Email.new()
      |> Swoosh.Email.from("sender@example.org")
      |> Swoosh.Email.to(c.subscription.email)

    assert {:error, :recipient_delivery_hold} = MailSafety.prepare(message, [])

    assert {:error, :recipient_delivery_hold} =
             MailSafety.prepare_sign_in(message, c.scope.user.id)

    refute_receive {:email, _}
  end

  test "missing timestamps, unmatched receipts and non-production attempts never apply actions",
       c do
    bad = Map.delete(event(c, "hardBounces"), "date")
    c.batch |> change(delivery_environment: "staging") |> Repo.update!()

    assert {:ok, %{"invalid" => 1, "unmatched" => 1, "new_events" => 0}} =
             ProviderReconciliation.reconcile([bad, event(c, "hardBounces")])

    assert Repo.aggregate(ProviderEvent, :count) == 0
    assert Newsletters.eligible?(c.subscription.email)
  end

  test "bounded pages persist a resumable cursor, overlap recent history and periodically sweep older late events",
       c do
    now = DateTime.utc_now()
    c.delivery |> change(attempted_at: DateTime.add(now, -30 * 86_400)) |> Repo.update!()
    parent = self()

    full_page = fn params ->
      send(parent, {:page, params})
      {:ok, List.duplicate(%{"event" => "delivered"}, ProviderHistory.page_size())}
    end

    assert {:ok, first} = ProviderSync.run(full_page, now)
    assert first.partial
    assert first.offset == 2000
    assert is_nil(first.cursor_at)

    for offset <- [0, 500, 1000, 1500] do
      assert_receive {:page, params}
      assert params[:offset] == offset
    end

    refute_receive {:page, _}

    final_page = fn params ->
      send(parent, {:continued, params})
      {:ok, [event(c, "hardBounces")]}
    end

    assert {:ok, completed} = ProviderSync.run(final_page, DateTime.add(now, 900))
    assert_receive {:continued, params}
    assert params[:offset] == 2000
    refute completed.partial
    assert completed.cursor_at == DateTime.add(now, 900)

    assert {:ok, _} =
             ProviderSync.run(
               fn params ->
                 send(parent, {:recent, params})
                 {:ok, []}
               end,
               DateTime.add(now, 1800)
             )

    assert_receive {:recent, recent}
    assert recent[:startDate] == Date.to_iso8601(Date.add(DateTime.to_date(now), -3))

    assert {:ok, _} =
             ProviderSync.run(
               fn params ->
                 send(parent, {:sweep, params})
                 {:ok, []}
               end,
               DateTime.add(now, 90_000)
             )

    assert_receive {:sweep, sweep}
    assert sweep[:startDate] == Date.to_iso8601(Date.add(DateTime.to_date(now), -30))
  end

  test "poll failures retain the cursor and existing holds; malformed responses cannot look like empty success",
       c do
    now = DateTime.utc_now()
    assert {:ok, _} = ProviderSync.run(fn _ -> {:ok, [event(c, "hardBounces")]} end, now)

    assert {:ok, failed} =
             ProviderSync.run(fn _ -> {:error, :rate_limited} end, DateTime.add(now, 900))

    assert failed.last_error == "rate_limited"
    assert failed.cursor_at == now
    assert ProviderReconciliation.address_suppressed?(c.subscription.email)

    assert {:ok, invalid} =
             ProviderSync.run(
               fn _ -> {:ok, [Map.delete(event(c, "unsubscribed"), "date")]} end,
               DateTime.add(now, 1800)
             )

    assert invalid.last_error == "invalid_events"
    assert invalid.counts["invalid"] == 1
  end

  test "literal provider timestamps persist through the ledger and newsletter withdrawal", c do
    cases = [
      {c, "hardBounces", "2026-10-15T12:34:56.000Z", ~U[2026-10-15 12:34:56.000000Z]},
      {receipt(c.scope, "seconds@example.org", "seconds-message"), "unsubscribed",
       "2026-10-15T12:34:56Z", ~U[2026-10-15 12:34:56.000000Z]},
      {receipt(c.scope, "milliseconds@example.org", "milliseconds-message"), "unsubscribed",
       "2026-10-15T12:34:56.123Z", ~U[2026-10-15 12:34:56.123000Z]},
      {receipt(c.scope, "microseconds@example.org", "microseconds-message"), "unsubscribed",
       "2026-10-15T12:34:56.123456Z", ~U[2026-10-15 12:34:56.123456Z]}
    ]

    for {fixture, kind, source_date, expected} <- cases do
      fixture.subscription
      |> change(
        requested_at: ~U[2026-10-01 00:00:00.000000Z],
        confirmed_at: ~U[2026-10-01 00:01:00.000000Z]
      )
      |> Repo.update!()

      fixture.delivery
      |> change(
        attempted_at: ~U[2026-10-15 01:00:00.000000Z],
        accepted_at: ~U[2026-10-15 01:00:01.000000Z]
      )
      |> Repo.update!()

      observation = event(fixture, kind) |> Map.put("date", source_date)

      assert {:ok, %{"new_events" => 1}} = ProviderReconciliation.reconcile([observation])
      recorded = Repo.get_by!(ProviderEvent, delivery_id: fixture.delivery.id)
      assert recorded.occurred_at == expected
      assert recorded.occurred_at.microsecond == expected.microsecond

      if kind == "unsubscribed" do
        subscription = Repo.get!(Subscription, fixture.subscription.id)
        assert subscription.state == "withdrawn"
        assert subscription.withdrawn_at == expected
        assert subscription.withdrawn_at.microsecond == expected.microsecond
        consent = Repo.get_by!(ConsentEvent, subscription_id: subscription.id, kind: "withdrawn")
        assert consent.evidence["observed_at"] == DateTime.to_iso8601(expected)
      end

      assert {:ok, %{"new_events" => 0, "already_recorded" => 1}} =
               ProviderReconciliation.reconcile([observation])
    end

    assert Repo.aggregate(ProviderEvent, :count) == 4
  end

  test "production opt-in and environment guards prevent staging polling and provider reads" do
    previous = Application.get_env(:pauseai_ca, :mail_environment)
    enabled = Application.get_env(:pauseai_ca, :newsletter_provider_sync_enabled)

    on_exit(fn ->
      Application.put_env(:pauseai_ca, :mail_environment, previous)
      Application.put_env(:pauseai_ca, :newsletter_provider_sync_enabled, enabled)
    end)

    Application.put_env(:pauseai_ca, :newsletter_provider_sync_enabled, true)

    for environment <- [:test, :dev, :staging, :blocked] do
      Application.put_env(:pauseai_ca, :mail_environment, environment)
      refute ProviderSyncWorker.enabled?()

      if environment != :test,
        do: assert({:error, :environment_blocked} = ProviderHistory.fetch_page([]))
    end

    Application.put_env(:pauseai_ca, :mail_environment, :production)
    assert ProviderSyncWorker.enabled?()
  end

  test "a separate database session holding the poll lock makes reconciliation busy without fetching or mutating" do
    opts =
      Repo.config() |> Keyword.take([:username, :password, :hostname, :database, :port, :ssl])

    connection = start_supervised!({Postgrex, opts})

    Postgrex.query!(
      connection,
      "SELECT pg_advisory_lock(hashtext('newsletter-provider-poll'))",
      []
    )

    try do
      assert {:error, :busy} = ProviderSync.run(fn _ -> flunk("busy poll must not fetch") end)
      assert is_nil(ProviderSync.status())
    after
      Postgrex.query!(
        connection,
        "SELECT pg_advisory_unlock(hashtext('newsletter-provider-poll'))",
        []
      )
    end
  end

  test "a legitimate empty Brevo report advances a quiet worker pass and clears prior errors" do
    keys = [
      :mail_environment,
      :newsletter_provider_sync_enabled,
      :brevo_api_key,
      :brevo_history_req_options
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:pauseai_ca, &1)})

    on_exit(fn ->
      for {key, old} <- previous do
        case old do
          {:ok, value} -> Application.put_env(:pauseai_ca, key, value)
          :error -> Application.delete_env(:pauseai_ca, key)
        end
      end
    end)

    Application.put_env(:pauseai_ca, :mail_environment, :production)
    Application.put_env(:pauseai_ca, :newsletter_provider_sync_enabled, true)
    Application.put_env(:pauseai_ca, :brevo_api_key, "synthetic")
    now = DateTime.utc_now()

    assert {:ok, %{last_error: "rate_limited"}} =
             ProviderSync.run(fn _ -> {:error, :rate_limited} end, now)

    for empty_body <- [%{}, %{"events" => []}] do
      Application.put_env(:pauseai_ca, :brevo_history_req_options,
        plug: fn conn -> Req.Test.json(conn, empty_body) end
      )

      assert {:ok, []} = ProviderHistory.fetch_page([])

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:noreply, nil} = ProviderSyncWorker.handle_info(:reconcile, nil)
        end)

      refute log =~ "Newsletter provider reconciliation"
      state = ProviderSync.status()
      assert is_nil(state.last_error)
      assert state.offset == 0
      refute state.partial
      assert DateTime.compare(state.cursor_at, now) in [:eq, :gt]
      assert state.last_success_at == state.cursor_at
      assert state.counts["new_events"] == 0
      assert state.counts["invalid"] == 0
      assert Repo.aggregate(ProviderEvent, :count) == 0
    end
  end

  test "results refresh updates statistics with activation off and reconciles only after fresh production activation",
       c do
    keys = [
      :mail_environment,
      :newsletter_provider_sync_enabled,
      :brevo_api_key,
      :brevo_history_req_options
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:pauseai_ca, &1)})

    on_exit(fn ->
      for {key, old} <- previous do
        case old do
          {:ok, value} -> Application.put_env(:pauseai_ca, key, value)
          :error -> Application.delete_env(:pauseai_ca, key)
        end
      end
    end)

    Application.put_env(:pauseai_ca, :brevo_api_key, "synthetic")
    provider_event = event(c, "hardBounces")

    Application.put_env(:pauseai_ca, :brevo_history_req_options,
      plug: fn conn -> Req.Test.json(conn, %{"events" => [provider_event]}) end
    )

    Application.put_env(:pauseai_ca, :newsletter_provider_sync_enabled, false)
    assert {:ok, _} = PauseAiCa.Newsletters.Results.refresh(c.scope, c.batch.id)
    assert Repo.aggregate(ProviderEvent, :count) == 0
    Application.put_env(:pauseai_ca, :mail_environment, :production)
    Application.put_env(:pauseai_ca, :newsletter_provider_sync_enabled, true)
    assert {:ok, _} = PauseAiCa.Newsletters.Results.refresh(c.scope, c.batch.id)
    assert Repo.aggregate(ProviderEvent, :count) == 1
    refute Newsletters.eligible?(c.subscription.email)

    Application.put_env(:pauseai_ca, :brevo_history_req_options,
      plug: fn conn -> Req.Test.json(conn, %{"unexpected" => "response shape"}) end
    )

    assert {:error, :invalid_response} = ProviderHistory.fetch_page([])

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:noreply, nil} = ProviderSyncWorker.handle_info(:reconcile, nil)
      end)

    assert log =~ "Newsletter provider reconciliation needs attention"
    assert ProviderSync.status().last_error == "invalid_response"
  end

  defp subscribe(email) do
    {:ok, requested} = Newsletters.request_signup(email, %{consent: true})
    {:ok, subscription} = Newsletters.confirm(requested.confirmation_token)

    subscription
    |> change(
      requested_at: DateTime.add(DateTime.utc_now(), -7200),
      confirmed_at: DateTime.add(DateTime.utc_now(), -7000)
    )
    |> Repo.update!()
  end

  defp pending_batch(scope, subscription) do
    {:ok, draft} = Drafts.create(scope)

    {:ok, draft} =
      Drafts.save(scope, draft, %{
        "subject" => "Synthetic review",
        "source" => "Synthetic message",
        "recipient_mode" => "newsletter",
        "recipient_keys" => [subscription.id]
      })

    {:ok, batch} = Batches.prepare(scope, draft, "newsletter", [subscription.id], true)
    batch
  end

  defp receipt(scope, email, provider_id) do
    subscription = subscribe(email)
    batch = pending_batch(scope, subscription)
    batch = batch |> change(delivery_environment: "production") |> Repo.update!()

    delivery =
      Repo.get_by!(Delivery, batch_id: batch.id)
      |> change(
        state: "accepted",
        authorizing_admin_id: scope.user.id,
        attempted_at: DateTime.add(DateTime.utc_now(), -3600),
        provider_id: provider_id
      )
      |> Repo.update!()

    %{subscription: subscription, batch: batch, delivery: delivery}
  end

  defp event(c, kind, reason \\ "") do
    %{
      "event" => kind,
      "messageId" => c.delivery.provider_id,
      "email" => c.delivery.email,
      "date" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -1800)),
      "reason" => reason
    }
  end
end
