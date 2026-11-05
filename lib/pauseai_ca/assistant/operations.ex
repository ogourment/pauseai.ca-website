defmodule PauseAiCa.Assistant.Operations do
  @moduledoc "Maintains actual operator delivery and independent audit evidence; it never calls a model."
  use GenServer
  import Ecto.Query
  alias PauseAiCa.{Assistant, Repo}
  alias PhoenixAgentAssistant.{AlertReceipt, AlertSink, Canonical, Store}
  alias PhoenixAgentAssistant.Store.Alert

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
    config = Assistant.configuration()
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
         Map.take(state, [:audit_anchor, :alerts, :fingerprint]) and
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
    store = Assistant.store()
    keys = config[:audit_keys]
    event = %{"kind" => "operations_readiness", "configuration_ref" => digest}

    with true <- alerts_resolved?(),
         {:ok, %{entry: entry}} <-
           Store.record(store, "system", "readiness/" <> digest, event, keys,
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
           Repo.get_by(Alert, namespace: store.namespace, audit_ref: alert_entry.id) do
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
