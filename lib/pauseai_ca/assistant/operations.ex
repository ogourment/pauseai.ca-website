defmodule PauseAiCa.Assistant.Operations do
  @moduledoc "Maintains actual operator delivery and independent audit evidence; it never calls a model."
  use GenServer
  import Ecto.Query
  alias PauseAiCa.{Assistant, Repo}

  alias PhoenixAgentAssistant.{
    AlertReceipt,
    AlertSink,
    Audit,
    Canonical,
    History,
    ReadinessReconciliation,
    Store
  }

  alias PhoenixAgentAssistant.Store.{Alert, AuditEntry, Stream}

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def status(config) do
    state = :persistent_term.get({__MODULE__, :status}, %{})

    fresh =
      state[:fingerprint] == fingerprint(config) and
        System.monotonic_time(:millisecond) - (state[:checked_at] || 0) < 65_000

    %{
      audit_anchor: fresh and state[:audit_anchor] == true,
      alerts: fresh and state[:alerts] == true and alerts_resolved?()
    }
  end

  defp alerts_resolved? do
    namespace = Assistant.store().namespace

    not Repo.exists?(
      from(a in Alert,
        where: a.namespace == ^namespace and a.state in ["submitting", "unknown", "failed"]
      )
    )
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  def invalidate do
    state = :persistent_term.get({__MODULE__, :status}, %{})

    :persistent_term.put(
      {__MODULE__, :status},
      Map.put(state, :audit_anchor, false)
    )

    :ok
  end

  def init(_) do
    Process.send_after(self(), :refresh, 1000)
    state = %{fingerprint: nil, checked_at: 0, audit_anchor: false, alerts: false}
    :persistent_term.put({__MODULE__, :status}, state)
    {:ok, state}
  end

  def handle_info(:refresh, state) do
    published = :persistent_term.get({__MODULE__, :status}, state)
    configured = Application.get_env(:pauseai_ca, :agent_assistant, [])
    config = if configured[:anchor], do: Assistant.configuration(), else: configured
    current = refresh(config)
    Process.send_after(self(), :refresh, 30_000)

    updated =
      Map.merge(
        state,
        Map.merge(current, %{
          fingerprint: fingerprint(config),
          checked_at: System.monotonic_time(:millisecond)
        })
      )

    :persistent_term.put({__MODULE__, :status}, updated)

    if Map.take(updated, [:audit_anchor, :alerts, :fingerprint]) !=
         Map.take(published, [:audit_anchor, :alerts, :fingerprint]) and
         Process.whereis(PauseAiCa.PubSub) do
      Phoenix.PubSub.broadcast(
        PauseAiCa.PubSub,
        "agent_assistant:settings",
        :assistant_settings_changed
      )
    end

    {:noreply, updated}
  end

  @doc false
  def refresh(config) do
    case {config[:anchor], config[:alert_delivery], config[:audit_keys]} do
      {anchor, alerts, keys} when is_list(anchor) and is_list(alerts) and is_map(keys) ->
        refresh_configured(config)

      _ ->
        %{audit_anchor: false, alerts: false}
    end
  rescue
    _ -> %{audit_anchor: false, alerts: false}
  catch
    _, _ -> %{audit_anchor: false, alerts: false}
  end

  defp refresh_configured(config) do
    digest = fingerprint(config)

    with true <- alerts_resolved?(),
         {:ok, {entry, alert_entry, alert}} <- recorded_probe(config, digest) do
      audit_ready =
        Assistant.anchor_entry(entry, config) == :ok and
          Assistant.anchor_entry(alert_entry, config) == :ok

      delivered =
        with {:ok, accepted} <- ensure_intake(alert, config),
             {:ok, _proof} <- AlertReceipt.fetch(accepted, config[:alert_delivery]),
             true <- alerts_resolved?(),
             do: true,
             else: (_ -> false)

      %{audit_anchor: audit_ready, alerts: delivered}
    else
      _ -> %{audit_anchor: false, alerts: false}
    end
  end

  @doc "Operator-only recovery; never enables the assistant or changes genuine security alerts."
  def reconcile_readiness_probe(scope, old_id, evidence) do
    config = Assistant.configuration()
    digest = fingerprint(config)

    with :ok <- recovery_guard(scope, config),
         {:ok, refs} <- recovery_evidence(evidence),
         {:ok, old} <- verified_old_probe(old_id, config),
         true <- old.correlation_id != digest,
         :ok <- replacement_config_guard(old, digest),
         {:ok, replacement_binding} <-
           ReadinessReconciliation.delivery_binding_ref(config[:alert_delivery]),
         true <- replacement_binding != refs["retired_delivery_binding_ref"],
         {:ok, {entry, alert_entry, alert}} <- recorded_probe(config, digest),
         :ok <- recovery_guard(scope, config),
         :ok <- Assistant.anchor_entry(entry, config),
         :ok <- recovery_guard(scope, config),
         :ok <- Assistant.anchor_entry(alert_entry, config),
         :ok <- recovery_guard(scope, config),
         {:ok, accepted} <- ensure_intake(alert, config),
         :ok <- recovery_guard(scope, config),
         {:ok, _} <- AlertReceipt.fetch(accepted, config[:alert_delivery]),
         :ok <- recovery_guard(scope, config) do
      result =
        Store.reconcile_readiness_probe(
          Assistant.store(),
          old.id,
          accepted.id,
          scope.user.id,
          config[:audit_keys],
          delivery: config[:alert_delivery],
          absence_evidence_ref: refs["absence_evidence_ref"],
          retired_delivery_binding_ref: refs["retired_delivery_binding_ref"],
          anchor_binding_ref: Canonical.digest(option_identity(config[:anchor])),
          anchor: fn transition ->
            with :ok <- recovery_guard(scope, config),
                 :ok <- Assistant.anchor_entry(transition, config),
                 :ok <- recovery_guard(scope, config),
                 do: :ok
          end
        )

      invalidate()
      result
    else
      false -> {:error, :unchanged_authority}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :readiness_recovery_unavailable}
    end
  rescue
    _ -> {:error, :readiness_recovery_unavailable}
  end

  defp replacement_config_guard(%Alert{state: "retired_authority"} = old, digest) do
    case Repo.get(Alert, get_in(old.receipt, ["retired_authority", "replacement_probe_ref"])) do
      %Alert{correlation_id: ^digest} -> :ok
      _ -> {:error, :already_reconciled}
    end
  end

  defp replacement_config_guard(_, _), do: :ok

  defp recovery_guard(scope, config) do
    current = Assistant.configuration()

    cond do
      not Assistant.eligible?(scope) ->
        {:error, :forbidden}

      Repo.in_transaction?() ->
        {:error, :durable_boundary_required}

      Store.enabled?(Assistant.store()) ->
        {:error, :assistant_must_be_off}

      Keyword.has_key?(config, :operations_adapter) or
        Keyword.has_key?(current, :operations_adapter) or not is_list(config[:anchor]) or
          not is_list(config[:alert_delivery]) ->
        {:error, :actual_operations_required}

      fingerprint(current) != fingerprint(config) ->
        {:error, :configuration_changed}

      true ->
        :ok
    end
  end

  defp recovery_evidence(evidence) when is_map(evidence) do
    if Enum.all?(Map.keys(evidence), &(is_atom(&1) or is_binary(&1))) do
      normalized = Map.new(evidence, fn {key, value} -> {to_string(key), value} end)

      if map_size(normalized) == map_size(evidence) and
           Enum.sort(Map.keys(normalized)) ==
             ~w(absence_evidence_ref retired_delivery_binding_ref) and
           Enum.all?(Map.values(normalized), &digest?/1),
         do: {:ok, normalized},
         else: {:error, :invalid_reconciliation_evidence}
    else
      {:error, :invalid_reconciliation_evidence}
    end
  end

  defp recovery_evidence(_), do: {:error, :invalid_reconciliation_evidence}

  defp verified_old_probe(id, config) do
    store = Assistant.store()

    with {:ok, ^id} <- Ecto.UUID.cast(id),
         %Alert{actor_id: "system", reason_code: "assistant_readiness", severity: "warning"} =
           alert <-
           Repo.get_by(Alert, id: id, namespace: store.namespace),
         true <-
           alert.state in ["unknown", "retired_authority"] and alert.receipt["attempts"] == 3,
         true <- digest?(alert.correlation_id),
         {:ok, []} <- History.read(store, "system", "operations", config[:audit_keys]),
         %AuditEntry{} = entry <- Repo.get(AuditEntry, alert.audit_ref),
         %Stream{namespace: namespace, actor_id: "system", reference: "operations"} <-
           Repo.get(Stream, entry.stream_id),
         true <- namespace == store.namespace,
         {:ok, event} <-
           Audit.open(
             entry.envelope,
             entry.stream_id,
             entry.previous,
             entry.sequence,
             config[:audit_keys]
           ),
         true <-
           entry.event_key == "readiness-alert/" <> alert.correlation_id and
             event["kind"] == "alert_queued" and event["reason"] == "assistant_readiness" and
             event["alert_intent"] == %{
               "reason_code" => "assistant_readiness",
               "severity" => "warning",
               "correlation_id" => alert.correlation_id
             },
         %AuditEntry{} = readiness <-
           Repo.get_by(AuditEntry,
             stream_id: entry.stream_id,
             event_key: "readiness/" <> alert.correlation_id
           ),
         {:ok, original} <-
           Audit.open(
             readiness.envelope,
             readiness.stream_id,
             readiness.previous,
             readiness.sequence,
             config[:audit_keys]
           ),
         true <-
           readiness.sequence < entry.sequence and original["kind"] == "operations_readiness" and
             original["configuration_ref"] == alert.correlation_id do
      {:ok, alert}
    else
      _ -> {:error, :not_synthetic_readiness_probe}
    end
  end

  defp digest?(value) when is_binary(value), do: Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp digest?(_), do: false

  defp recorded_probe(config, digest) do
    store = Assistant.store()
    keys = config[:audit_keys]

    with {:ok, %{entry: entry}} <-
           Store.record(
             store,
             "system",
             "readiness/" <> digest,
             %{"kind" => "operations_readiness", "configuration_ref" => digest},
             keys,
             stream: "operations"
           ),
         {:ok, %{entry: alert_entry}} <-
           Store.queue_alert(
             store,
             "system",
             "readiness-alert/" <> digest,
             :assistant_readiness,
             keys,
             correlation_id: digest,
             stream: "operations"
           ),
         %Alert{} = alert <-
           Repo.get_by(Alert, namespace: store.namespace, audit_ref: alert_entry.id),
         do: {:ok, {entry, alert_entry, alert}}
  end

  defp ensure_intake(%Alert{state: "accepted"} = alert, _config), do: {:ok, alert}

  defp ensure_intake(alert, config) do
    claim =
      if alert.state == "pending",
        do: Store.claim_alert(Assistant.store(), alert.id, config[:audit_keys]),
        else: Store.retry_alert(Assistant.store(), alert.id, config[:audit_keys])

    with {:ok, _} <- claim do
      result = AlertSink.deliver(alert, config[:alert_delivery])

      {state, receipt} =
        case result do
          {:ok, value} -> {"accepted", value}
          {:error, :rejected} -> {"failed", %{"reason" => "rejected"}}
          _ -> {"unknown", %{"reason" => "unconfirmed_intake"}}
        end

      with {:ok, row} <-
             Store.finish_alert(Assistant.store(), alert.id, state, receipt, config[:audit_keys]),
           true <- state == "accepted",
           do: {:ok, row},
           else: (_ -> {:error, :unconfirmed_intake})
    end
  end

  @doc false
  def fingerprint(config) do
    provider =
      case config[:provider] do
        {module, opts} -> %{module: to_string(module), credential: hash(opts[:api_key])}
        _ -> nil
      end

    audit = config[:audit_keys] || %{}

    payload = %{
      "provider" => provider,
      "models" => config[:models] || %{},
      "reviews" =>
        Map.new(config[:safety] || [], fn {stage, {module, options}} ->
          {to_string(stage),
           %{
             module: to_string(module),
             credential_ref: hash(options[:api_key]),
             model: options[:model]
           }}
        end),
      "anchor" => option_identity(config[:anchor] || []),
      "alerts" => option_identity(config[:alert_delivery] || []),
      "audit" => %{
        "id" => audit[:id],
        "encryption_ref" => hash(audit[:encryption]),
        "signing_ref" => hash(audit[:signing])
      },
      "pricing" => config[:pricing] || %{}
    }

    # Omitted and explicit strict_v1 share the existing identity. A new policy
    # must invalidate readiness; old proof cannot authorize different cutoffs.
    payload =
      case Keyword.get(config, :safety_policy, :strict_v1) do
        :strict_v1 -> payload
        policy -> Map.put(payload, "safety_policy", to_string(policy))
      end

    payload =
      Enum.reduce([:pilot_budget, :instruction_binding], payload, fn key, current ->
        if Keyword.has_key?(config, key),
          do: Map.put(current, Atom.to_string(key), config[key]),
          else: current
      end)

    payload |> Jason.encode!() |> Jason.decode!() |> Canonical.digest()
  end

  defp option_identity(options) do
    Map.new(options, fn
      {:token, value} -> {"credential_ref", hash(value)}
      {:public_key, value} -> {"public_key", Base.encode64(value)}
      {key, value} when is_binary(value) -> {to_string(key), value}
      {key, value} when is_boolean(value) -> {to_string(key), value}
      {key, _} -> {to_string(key), "server-adapter"}
    end)
  end

  defp hash(value) when is_binary(value),
    do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)

  defp hash(_), do: nil
end
