defmodule PauseAiCa.Assistant.OperationsTest do
  use PauseAiCa.DataCase, async: false
  alias PauseAiCa.{Assistant, AssistantFixtures}
  alias PauseAiCa.Assistant.Operations
  alias PhoenixAgentAssistant.{Anchor, Audit, Canonical}
  alias PhoenixAgentAssistant.Store.{Alert, AuditEntry}

  @base "/api/assistant/audit-anchors"

  setup do
    worker = Process.whereis(Operations)
    if worker, do: :sys.suspend(worker)
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

      if worker && Process.alive?(worker), do: :sys.resume(worker)
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
             decision: "delivered"
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
    %{config: config, remote: remote}
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
            "delivered_at" =>
              DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.to_iso8601()
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

  defp assert_bearer(conn, token),
    do: assert(Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> token])

  defp json(conn, body, status \\ 200),
    do: Req.Test.json(Plug.Conn.put_status(conn, status), body)
end
