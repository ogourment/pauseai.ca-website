defmodule PauseAiCa.Assistant.OperationsTest do
  use PauseAiCa.DataCase, async: false
  alias PauseAiCa.{Assistant, AssistantFixtures}
  alias PauseAiCa.Assistant.Operations
  alias PhoenixAgentAssistant.{Anchor, Audit, Canonical, ReadinessReconciliation, Store}
  alias PhoenixAgentAssistant.Store.{Alert, AuditEntry}

  @base "/api/assistant/audit-anchors"

  setup do
    workers =
      [Operations, PauseAiCa.Assistant.AlertWorker]
      |> Enum.map(&Process.whereis/1)
      |> Enum.reject(&is_nil/1)

    Enum.each(workers, &:sys.suspend/1)
    previous = Application.fetch_env(:pauseai_ca, :agent_assistant)
    status_key = {Operations, :status}
    previous_status = :persistent_term.get(status_key, :missing)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pauseai_ca, :agent_assistant, value)
        :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
      end

      if previous_status == :missing,
        do: :persistent_term.erase(status_key),
        else: :persistent_term.put(status_key, previous_status)

      for worker <- workers, Process.alive?(worker), do: :sys.resume(worker)
    end)

    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    signing = [key_id: "synthetic-authority-v1", private_key: private]
    recipient = Canonical.digest(%{"channel" => "telegram", "chat_id" => "-100123456789"})

    remote =
      start_supervised!(
        {Agent,
         fn ->
           %{
             journal: [],
             anchor_posts: 0,
             alert_posts: [],
             recipient: recipient,
             current_recipient: recipient,
             decision: "delivered",
             delivered_at:
               DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.to_iso8601()
           }
         end}
      )

    plug = {Req.Test, __MODULE__}

    config =
      AssistantFixtures.configuration(self())
      |> Keyword.delete(:operations_adapter)
      |> Keyword.put(:anchor,
        endpoint: "https://ops.example.invalid" <> @base <> "/journal",
        namespace: Assistant.store().namespace,
        token: "synthetic-anchor-token",
        key_id: "synthetic-authority-v1",
        public_key: public,
        plug: plug
      )
      |> Keyword.put(:alert_delivery,
        endpoint: "https://ops.example.invalid/api/alerts",
        token: "synthetic-alert-token",
        producer: "synthetic-pauseai",
        app: "synthetic-app",
        environment: "synthetic-staging",
        recipient_ref: recipient,
        plug: plug
      )

    refute Keyword.has_key?(config, :operations_adapter)
    Application.put_env(:pauseai_ca, :agent_assistant, config)
    Req.Test.stub(__MODULE__, fn conn -> route(conn, remote, signing) end)
    %{config: config, remote: remote, signing: signing}
  end

  test "readiness evidence changes with safety policy while equivalent strict config preserves it",
       c do
    strict = Operations.fingerprint(c.config)
    assert strict == Operations.fingerprint(Keyword.put(c.config, :safety_policy, :strict_v1))

    refute strict ==
             Operations.fingerprint(Keyword.put(c.config, :safety_policy, :text_coaching_v1))

    :persistent_term.put({Operations, :status}, %{
      fingerprint: strict,
      checked_at: System.monotonic_time(:millisecond),
      audit_anchor: true,
      alerts: true
    })

    assert Operations.status(c.config) == %{audit_anchor: true, alerts: true}

    assert Operations.status(Keyword.put(c.config, :safety_policy, :text_coaching_v1)) == %{
             audit_anchor: false,
             alerts: false
           }
  end

  test "operator recovery retains the old eight events and requires new delivery and anchors",
       c do
    {scope, old, evidence, original} = recovery_fixture(c)
    assert Operations.refresh(c.config) == %{audit_anchor: false, alerts: false}

    assert {:ok, %{alert: retired, entry: intent, replayed?: false}} =
             Operations.reconcile_readiness_probe(scope, old.id, evidence)

    assert retired.state == "retired_authority"
    assert Map.delete(retired.receipt, "retired_authority") == old.receipt
    assert retired.receipt["attempts"] == 3
    assert retired.receipt["retired_authority"]["audit_ref"] == intent.id
    assert_original_events(original)
    refute Store.enabled?(Assistant.store())
    remote = Agent.get(c.remote, & &1)
    assert length(remote.alert_posts) == 1
    assert remote.anchor_posts == 3
    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: true}

    assert {:ok, %{replayed?: true, entry: ^intent}} =
             Operations.reconcile_readiness_probe(scope, old.id, evidence)

    assert Agent.get(c.remote, & &1) == remote
    assert_original_events(original)
    refute_received {:assistant_generated, _, _}
  end

  test "pending replacement remains blocking and retry reuses its accepted intake", c do
    {scope, old, evidence, original} = recovery_fixture(c)
    Agent.update(c.remote, &%{&1 | decision: "pending"})
    assert {:error, _} = Operations.reconcile_readiness_probe(scope, old.id, evidence)
    assert Repo.get!(Alert, old.id) == old
    assert_original_events(original)
    assert Operations.refresh(c.config).alerts == false
    assert length(Agent.get(c.remote, & &1.alert_posts)) == 1
    Agent.update(c.remote, &%{&1 | decision: "delivered"})
    assert {:ok, _} = Operations.reconcile_readiness_probe(scope, old.id, evidence)
    assert length(Agent.get(c.remote, & &1.alert_posts)) == 1
  end

  test "a genuine security alert remains untouched and blocks readiness after probe recovery",
       c do
    {scope, old, evidence, _} = recovery_fixture(c)

    assert {:ok, %{entry: entry}} =
             Store.queue_alert(
               Assistant.store(),
               "system",
               "genuine-security",
               :unsafe_request,
               c.config[:audit_keys],
               correlation_id: Ecto.UUID.generate(),
               stream: "operations"
             )

    genuine = Repo.get_by!(Alert, audit_ref: entry.id)
    assert {:ok, _} = Store.claim_alert(Assistant.store(), genuine.id, c.config[:audit_keys])

    assert {:ok, genuine} =
             Store.finish_alert(
               Assistant.store(),
               genuine.id,
               "unknown",
               %{"reason" => "unconfirmed_intake"},
               c.config[:audit_keys]
             )

    assert {:error, :not_synthetic_readiness_probe} =
             Operations.reconcile_readiness_probe(scope, genuine.id, evidence)

    assert Agent.get(c.remote, & &1.anchor_posts) == 0
    assert {:ok, _} = Operations.reconcile_readiness_probe(scope, old.id, evidence)
    assert Repo.get!(Alert, genuine.id) == genuine
    refute Operations.refresh(c.config).alerts
  end

  test "fresh authorization and exact evidence are checked before any external effects", c do
    {scope, old, evidence, _} = recovery_fixture(c)
    before = Agent.get(c.remote, & &1)
    count = Repo.aggregate(AuditEntry, :count)
    assert {:error, :forbidden} = Operations.reconcile_readiness_probe(nil, old.id, evidence)
    Repo.update!(Ecto.Changeset.change(scope.user, superadmin: false))
    assert {:error, :forbidden} = Operations.reconcile_readiness_probe(scope, old.id, evidence)

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(PauseAiCa.Accounts.User, scope.user.id), superadmin: true)
    )

    assert {:error, :invalid_reconciliation_evidence} =
             Operations.reconcile_readiness_probe(
               scope,
               old.id,
               Map.put(evidence, "endpoint", "https://evil.invalid")
             )

    assert {:error, :invalid_reconciliation_evidence} =
             Operations.reconcile_readiness_probe(
               scope,
               old.id,
               Map.put(evidence, :absence_evidence_ref, evidence["absence_evidence_ref"])
             )

    assert Repo.aggregate(AuditEntry, :count) == count
    assert Agent.get(c.remote, & &1) == before
  end

  test "fixture adapters and enabled assistant cannot use operator recovery", c do
    {scope, old, evidence, _} = recovery_fixture(c)

    Application.put_env(
      :pauseai_ca,
      :agent_assistant,
      Keyword.put(c.config, :operations_adapter, {AssistantFixtures.Operations, []})
    )

    assert {:error, :actual_operations_required} =
             Operations.reconcile_readiness_probe(scope, old.id, evidence)

    Application.put_env(:pauseai_ca, :agent_assistant, c.config)

    assert {:ok, _} =
             Store.set_enabled(
               Assistant.store(),
               scope.user.id,
               true,
               "enabled-fixture",
               c.config[:audit_keys]
             )

    assert {:error, :assistant_must_be_off} =
             Operations.reconcile_readiness_probe(scope, old.id, evidence)

    assert Agent.get(c.remote, & &1.anchor_posts) == 0
    assert Agent.get(c.remote, & &1.alert_posts) == []
  end

  test "cryptographic provenance failure never creates replacement evidence", c do
    {scope, old, evidence, _} = recovery_fixture(c)
    entry = Repo.get!(AuditEntry, old.audit_ref)

    Repo.update!(
      Ecto.Changeset.change(entry,
        envelope: Map.put(entry.envelope, "digest", String.duplicate("0", 64))
      )
    )

    count = Repo.aggregate(AuditEntry, :count)

    assert {:error, :not_synthetic_readiness_probe} =
             Operations.reconcile_readiness_probe(scope, old.id, evidence)

    assert Repo.aggregate(AuditEntry, :count) == count
    assert Agent.get(c.remote, & &1.anchor_posts) == 0
    assert Agent.get(c.remote, & &1.alert_posts) == []
  end

  test "permission loss during retirement anchoring preserves durable intent and old blocking state",
       c do
    {scope, old, evidence, original} = recovery_fixture(c)

    Req.Test.stub(__MODULE__, fn conn ->
      response = route(conn, c.remote, c.signing)

      if conn.method == "POST" and conn.request_path == @base and
           Agent.get(c.remote, & &1.anchor_posts) == 3 do
        Repo.update!(Ecto.Changeset.change(scope.user, superadmin: false))
      end

      response
    end)

    assert {:error, :transition_unanchored} =
             Operations.reconcile_readiness_probe(scope, old.id, evidence)

    assert Repo.get!(Alert, old.id) == old
    assert_original_events(original)
    assert Agent.get(c.remote, & &1.anchor_posts) == 3
    refute Operations.refresh(c.config).alerts

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(PauseAiCa.Accounts.User, scope.user.id), superadmin: true)
    )

    anchored = Agent.get(c.remote, & &1.journal)
    Req.Test.stub(__MODULE__, fn conn -> route(conn, c.remote, c.signing) end)
    assert {:ok, _} = Operations.reconcile_readiness_probe(scope, old.id, evidence)
    assert Agent.get(c.remote, & &1.journal) == anchored
    assert length(Agent.get(c.remote, & &1.alert_posts)) == 1
  end

  test "both checks become ready only with encrypted local anchors and exact Telegram receipt",
       c do
    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: true}
    state = Agent.get(c.remote, & &1)
    assert length(state.journal) == 2
    assert state.anchor_posts == 2
    assert [payload] = state.alert_posts
    assert payload["category"] == "assistant_security"
    refute Map.has_key?(payload, "actor_id")
    refute Map.has_key?(payload, "text")

    for receipt <- state.journal do
      entry = Repo.get!(AuditEntry, receipt["nonce"])

      assert {:ok, event} =
               Audit.open(
                 entry.envelope,
                 entry.stream_id,
                 entry.previous,
                 entry.sequence,
                 c.config[:audit_keys]
               )

      assert event["namespace"] == Assistant.store().namespace

      assert receipt["digest"] ==
               Canonical.digest(%{
                 "entry" => entry.id,
                 "stream" => entry.stream_id,
                 "sequence" => entry.sequence,
                 "envelope" => entry.envelope["digest"]
               })

      assert {:ok, _} =
               Anchor.verify(
                 receipt,
                 Map.take(
                   receipt,
                   ~w(namespace stream sequence digest previous nonce)
                 ),
                 c.config[:anchor]
               )

      refute inspect(entry.envelope) =~ "operations_readiness"
    end

    alert = Repo.get_by!(Alert, namespace: Assistant.store().namespace)
    assert alert.state == "accepted"
    assert alert.receipt["event_id"] == "12345"
    assert payload["idempotency_key"] == "assistant:" <> alert.id
    refute_received {:assistant_generated, _, _}
  end

  test "repeated unchanged configuration reuses anchors and the same accepted alert", c do
    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: true}
    first = Agent.get(c.remote, & &1)
    digest = Operations.fingerprint(c.config)

    assert {:ok, %{entry: entry, replayed?: true}} =
             PhoenixAgentAssistant.Store.record(
               Assistant.store(),
               "system",
               "readiness/" <> digest,
               %{"kind" => "operations_readiness", "configuration_ref" => digest},
               c.config[:audit_keys],
               stream: "operations"
             )

    assert :ok = Assistant.anchor_entry(entry, c.config)

    assert {:ok, %{entry: alert_entry, replayed?: true}} =
             PhoenixAgentAssistant.Store.queue_alert(
               Assistant.store(),
               "system",
               "readiness-alert/" <> digest,
               :assistant_readiness,
               c.config[:audit_keys],
               correlation_id: digest,
               stream: "operations"
             )

    assert :ok = Assistant.anchor_entry(alert_entry, c.config)
    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: true}
    second = Agent.get(c.remote, & &1)
    assert second.journal == first.journal
    assert second.anchor_posts == 2
    assert second.alert_posts == first.alert_posts
    assert length(second.alert_posts) == 1

    assert Repo.aggregate(
             from(a in Alert, where: a.namespace == ^Assistant.store().namespace),
             :count
           ) == 1

    refute_received {:assistant_generated, _, _}
  end

  for state <- ~w(submitting unknown failed) do
    test "#{state} alert blocks cached and refreshed readiness until reconciled", c do
      cache_ready(c.config)
      alert = alert_in_state(Assistant.store(), unquote(state), c.config)
      remote_before = Agent.get(c.remote, & &1)

      assert Operations.status(c.config) == %{audit_anchor: true, alerts: false}
      assert Operations.refresh(c.config) == %{audit_anchor: false, alerts: false}
      # A new successful configuration proof must not hide an older incident.
      changed =
        Keyword.put(
          c.config,
          :models,
          Map.put(c.config[:models], "unused", %{model: "changed-fixture"})
        )

      assert Operations.refresh(changed) == %{audit_anchor: false, alerts: false}
      assert Agent.get(c.remote, & &1) == remote_before
      assert Repo.get!(Alert, alert.id).state == unquote(state)
      refute_received {:assistant_generated, _, _}
    end
  end

  test "unresolved other-namespace alerts do not block this namespace", c do
    other = Store.new(Repo, "unrelated-assistant-fixture")
    for state <- ~w(submitting unknown failed), do: alert_in_state(other, state, c.config)
    cache_ready(c.config)
    assert Operations.status(c.config) == %{audit_anchor: true, alerts: true}
    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: true}
  end

  test "pending alerts retain readiness and bounded worker bootstrap eligibility", c do
    cache_ready(c.config)
    pending = alert_in_state(Assistant.store(), "pending", c.config)
    assert Operations.status(c.config).alerts
    assert Operations.refresh(c.config).alerts
    assert {:ok, store, _, options} = Assistant.alert_worker_configuration()
    assert store.namespace == Assistant.store().namespace
    assert options[:route_verified]
    assert {:ok, retryable} = Store.retryable_alerts(store, 5)
    assert Enum.any?(retryable, &(&1.id == pending.id))
  end

  test "repository query failure overrides a fresh successful cached proof", c do
    cache_ready(c.config)
    remote_before = Agent.get(c.remote, & &1)
    previous = Repo.put_dynamic_repo(:assistant_unavailable_fixture_repo)

    try do
      assert Operations.status(c.config) == %{audit_anchor: true, alerts: false}
      assert Operations.refresh(c.config) == %{audit_anchor: false, alerts: false}
    after
      Repo.put_dynamic_repo(previous)
    end

    assert Operations.status(c.config).alerts
    assert Agent.get(c.remote, & &1) == remote_before
  end

  test "an unresolved alert appearing during a successful receipt check prevents green refresh",
       c do
    cache_ready(c.config)

    Req.Test.stub(__MODULE__, fn conn ->
      if conn.method == "GET" and conn.request_path == "/api/alerts/12345/receipt" do
        alert_in_state(Assistant.store(), "failed", c.config)
      end

      route(conn, c.remote, c.signing)
    end)

    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: false}
    refute Operations.status(c.config).alerts
  end

  test "accepted intake with the wrong Telegram recipient never makes alerts ready", c do
    Agent.update(c.remote, &%{&1 | recipient: String.duplicate("b", 64)})
    result = Operations.refresh(c.config)
    assert result.alerts == false
    assert length(Agent.get(c.remote, & &1.journal)) == 2
    assert Repo.get_by!(Alert, namespace: Assistant.store().namespace).state == "accepted"
  end

  test "changing the live operator route invalidates old delivery without another alert", c do
    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: true}
    first = Agent.get(c.remote, & &1)
    Agent.update(c.remote, &%{&1 | current_recipient: String.duplicate("d", 64)})
    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: false}
    after_change = Agent.get(c.remote, & &1)
    assert after_change.journal == first.journal
    assert after_change.alert_posts == first.alert_posts
  end

  test "pending intake decision is not delivery proof", c do
    Agent.update(c.remote, &%{&1 | decision: "pending"})
    assert Operations.refresh(c.config).alerts == false
    assert length(Agent.get(c.remote, & &1.alert_posts)) == 1
  end

  test "tampered encrypted row at independent head prevents any further readiness", c do
    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: true}
    before = Agent.get(c.remote, & &1)
    last = List.last(before.journal)
    entry = Repo.get!(AuditEntry, last["nonce"])
    corrupted = Map.put(entry.envelope, "tag", Base.encode64(:crypto.strong_rand_bytes(16)))
    Repo.update_all(from(e in AuditEntry, where: e.id == ^entry.id), set: [envelope: corrupted])
    assert Operations.refresh(c.config) == %{audit_anchor: false, alerts: false}
    after_state = Agent.get(c.remote, & &1)
    assert after_state.journal == before.journal
    assert after_state.alert_posts == before.alert_posts
  end

  test "missing local row for retained external head detects rollback without new effects", c do
    assert Operations.refresh(c.config) == %{audit_anchor: true, alerts: true}
    before = Agent.get(c.remote, & &1)
    last = List.last(before.journal)
    Repo.delete_all(from(a in Alert, where: a.audit_ref == ^last["nonce"]))
    assert {1, _} = Repo.delete_all(from(e in AuditEntry, where: e.id == ^last["nonce"]))
    assert Operations.refresh(c.config) == %{audit_anchor: false, alerts: false}
    after_state = Agent.get(c.remote, & &1)
    assert after_state.journal == before.journal
    assert after_state.alert_posts == before.alert_posts
  end

  defp route(conn, remote, signing) do
    assert conn.host == "ops.example.invalid"
    assert conn.query_string == ""

    cond do
      conn.method == "GET" and conn.request_path == @base <> "/journal" ->
        assert_bearer(conn, "synthetic-anchor-token")
        json(conn, %{"receipt" => Agent.get(remote, &List.last(&1.journal))})

      conn.method == "GET" and
          String.starts_with?(conn.request_path, @base <> "/journal/receipts/") ->
        assert_bearer(conn, "synthetic-anchor-token")
        nonce = String.replace_prefix(conn.request_path, @base <> "/journal/receipts/", "")

        receipt =
          Agent.get(remote, fn state -> Enum.find(state.journal, &(&1["nonce"] == nonce)) end)

        json(conn, %{"receipt" => receipt}, if(receipt, do: 200, else: 404))

      conn.method == "POST" and conn.request_path == @base ->
        assert_bearer(conn, "synthetic-anchor-token")
        append_anchor(conn, remote, signing)

      conn.method == "POST" and conn.request_path == "/api/alerts" ->
        assert_bearer(conn, "synthetic-alert-token")
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        Agent.update(remote, &%{&1 | alert_posts: &1.alert_posts ++ [payload]})

        json(
          conn,
          %{
            "contract_version" => "alert-event.v1",
            "duplicate" => false,
            "event" => %{
              "id" => 12345,
              "producer" => "synthetic-pauseai",
              "decision" => "pending"
            }
          },
          202
        )

      conn.method == "GET" and conn.request_path == "/api/alerts/12345/receipt" ->
        assert_bearer(conn, "synthetic-alert-token")
        state = Agent.get(remote, & &1)
        payload = List.last(state.alert_posts)

        json(conn, %{
          "current_recipient_ref" => state.current_recipient,
          "event" => %{
            "id" => 12345,
            "producer" => "synthetic-pauseai",
            "app" => payload["app"],
            "environment" => payload["environment"],
            "idempotency_key" => payload["idempotency_key"],
            "decision" => state.decision,
            "delivered_at" => state.delivered_at
          },
          "delivery" => %{
            "channel" => "telegram",
            "routing" => "application",
            "recipient_ref" => state.recipient,
            "message_ids" => [17]
          }
        })

      true ->
        flunk("unexpected controlled operations route")
    end
  end

  defp append_anchor(conn, remote, signing) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    request = Jason.decode!(body)
    assert Anchor.request?(request)
    assert request["stream"] == "journal"

    receipt =
      Agent.get_and_update(remote, fn state ->
        head = List.last(state.journal)
        assert request["sequence"] == if(head, do: head["sequence"] + 1, else: 1)
        assert request["previous"] == if(head, do: head["digest"], else: "")

        {:ok, receipt} =
          Anchor.sign(
            Map.put(request, "observed_at", DateTime.utc_now() |> DateTime.to_iso8601()),
            signing
          )

        {receipt,
         %{state | journal: state.journal ++ [receipt], anchor_posts: state.anchor_posts + 1}}
      end)

    json(conn, %{"receipt" => receipt}, 201)
  end

  defp cache_ready(config) do
    assert Operations.refresh(config) == %{audit_anchor: true, alerts: true}

    :persistent_term.put({Operations, :status}, %{
      fingerprint: Operations.fingerprint(config),
      checked_at: System.monotonic_time(:millisecond),
      audit_anchor: true,
      alerts: true
    })

    assert Operations.status(config).alerts
  end

  defp alert_in_state(store, state, config) do
    assert {:ok, %{entry: entry}} =
             Store.queue_alert(
               store,
               "system",
               "readiness-regression/" <> Ecto.UUID.generate(),
               :assistant_readiness,
               config[:audit_keys],
               correlation_id: Ecto.UUID.generate()
             )

    alert = Repo.get_by!(Alert, namespace: store.namespace, audit_ref: entry.id)

    if state != "pending",
      do: assert({:ok, _} = Store.claim_alert(store, alert.id, config[:audit_keys]))

    if state in ["unknown", "failed"],
      do:
        assert(
          {:ok, _} =
            Store.finish_alert(
              store,
              alert.id,
              state,
              %{"reason" => "synthetic-regression"},
              config[:audit_keys]
            )
        )

    Repo.get!(Alert, alert.id)
  end

  defp recovery_fixture(c) do
    user = PauseAiCa.AccountsFixtures.user_fixture()
    user = Repo.update!(Ecto.Changeset.change(user, superadmin: true))
    scope = PauseAiCa.Accounts.Scope.for_user(user)
    store = Assistant.store()

    old_delivery =
      Keyword.put(
        c.config[:alert_delivery],
        :endpoint,
        "https://old.ops.example.invalid/api/alerts"
      )

    old_config = Keyword.put(c.config, :alert_delivery, old_delivery)
    digest = Operations.fingerprint(old_config)

    assert {:ok, _} =
             Store.record(
               store,
               "system",
               "readiness/" <> digest,
               %{"kind" => "operations_readiness", "configuration_ref" => digest},
               c.config[:audit_keys],
               stream: "operations"
             )

    assert {:ok, %{entry: entry}} =
             Store.queue_alert(
               store,
               "system",
               "readiness-alert/" <> digest,
               :assistant_readiness,
               c.config[:audit_keys],
               correlation_id: digest,
               stream: "operations"
             )

    old = Repo.get_by!(Alert, audit_ref: entry.id)

    for attempt <- 1..3 do
      if attempt == 1 do
        assert {:ok, _} = Store.claim_alert(store, old.id, c.config[:audit_keys])
      else
        Repo.update_all(from(a in Alert, where: a.id == ^old.id),
          set: [updated_at: DateTime.utc_now() |> DateTime.add(-61, :second)]
        )

        assert {:ok, _} = Store.retry_alert(store, old.id, c.config[:audit_keys])
      end

      assert {:ok, _} =
               Store.finish_alert(
                 store,
                 old.id,
                 "unknown",
                 %{"reason" => "unconfirmed_intake"},
                 c.config[:audit_keys]
               )
    end

    original = Repo.all(AuditEntry)
    assert length(original) == 8
    assert {:ok, binding} = ReadinessReconciliation.delivery_binding_ref(old_delivery)

    {scope, Repo.get!(Alert, old.id),
     %{
       "absence_evidence_ref" => Canonical.digest(%{"reviewed" => "old-authority-absence"}),
       "retired_delivery_binding_ref" => binding
     }, original}
  end

  defp assert_original_events(original) do
    for entry <- original, do: assert(Repo.get!(AuditEntry, entry.id) == entry)
  end

  defp assert_bearer(conn, token),
    do: assert(Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> token])

  defp json(conn, body, status \\ 200),
    do: Req.Test.json(Plug.Conn.put_status(conn, status), body)
end
