defmodule PauseAiCa.Assistant do
  @moduledoc "Consumer-owned assistant permissions, configuration and durable host adapter."
  @behaviour PhoenixAgentAssistant.Host
  import Ecto.Query
  alias PhoenixAgentAssistant.{Catalog, History, Modes, Runner, Store}
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.Scope

  def store, do: Store.new(Repo, "pauseai-canada")

  @external_resource Path.expand("../../priv/assistant/coaching.md", __DIR__)
  @coaching File.read!(@external_resource)

  def configuration do
    config =
      Keyword.merge(
        [
          daily_token_limit: 100_000,
          max_daily_token_limit: 1_000_000,
          max_turn_tokens: 32_768,
          max_output_tokens: 1024
        ],
        Application.get_env(:pauseai_ca, :agent_assistant, [])
      )

    config = with_feature_evidence(config)

    case config[:provider] do
      {module, options} when is_list(options) ->
        Keyword.put(config, :provider, {module, Keyword.put(options, :instructions, @coaching)})

      _ ->
        config
    end
  end

  defp with_feature_evidence(config) do
    if Keyword.has_key?(config, :features) do
      config
    else
      identity =
        Map.put(
          AcceptanceHarness.Health.payload(),
          :source_sha,
          System.get_env("PAUSEAI_CA_GIT_SHA")
        )

      case PauseAiCa.Assistant.FeatureCatalogue.load(identity) do
        {:ok, catalogue} -> Keyword.merge(config, Map.to_list(catalogue))
        _ -> config
      end
    end
  end

  def alert_worker_configuration do
    config = configuration()
    options = config[:alert_delivery] || []

    if config[:alert_delivery_verified] == true and options[:route_verified] == true and
         valid_keys?(config[:audit_keys] || %{}) do
      {:ok, store(), config[:audit_keys], options}
    else
      :disabled
    end
  end

  def eligible?(scope), do: Volunteers.superadmin?(scope)
  def visible?(scope), do: eligible?(scope) and Store.enabled?(store()) and readiness() == []

  def readiness do
    config = configuration()
    keys = config[:audit_keys] || %{}

    checks = [
      {:audit_keys, valid_keys?(keys)},
      {:models,
       Enum.all?(
         ~w(fast normal high),
         &match?({:ok, _}, Modes.resolve(&1, config[:models] || %{}))
       )},
      {:provider, configured?(config[:provider])},
      {:moderation, configured?(get_in(config, [:safety, :moderation]))},
      {:jev, configured?(get_in(config, [:safety, :jev]))},
      {:budget,
       is_integer(config[:daily_limit_micros]) and config[:daily_limit_micros] > 0 and
         is_integer(config[:max_turn_cost_micros]) and config[:max_turn_cost_micros] > 0 and
         is_integer(config[:daily_token_limit]) and config[:daily_token_limit] >= 0 and
         is_integer(config[:max_daily_token_limit]) and
         config[:max_daily_token_limit] in 0..1_000_000_000 and
         is_integer(config[:max_turn_tokens]) and config[:max_turn_tokens] > 0},
      {:operator_alerts, config[:alert_delivery_verified] == true},
      {:audit_anchor, config[:audit_anchor_verified] == true},
      {:price_policy, config[:price_policy_verified] == true},
      {:feature_catalogue, catalogue_ready?(config)}
    ]

    for {name, false} <- checks, do: name
  end

  def set_enabled(scope, value) when is_boolean(value) do
    with true <- eligible?(scope),
         true <- not value or readiness() == [] do
      result =
        Store.set_enabled(
          store(),
          actor(scope),
          value,
          Ecto.UUID.generate(),
          configuration()[:audit_keys]
        )

      if match?({:ok, _}, result),
        do:
          Phoenix.PubSub.broadcast(
            PauseAiCa.PubSub,
            "agent_assistant:settings",
            :assistant_settings_changed
          )

      result
    else
      _ -> {:error, :not_ready}
    end
  end

  def mode(scope) do
    if eligible?(scope), do: Store.mode(store(), actor(scope)), else: {:error, :forbidden}
  end

  def set_mode(scope, mode) do
    config = configuration()

    with true <- visible?(scope),
         {:ok, _} <- Modes.resolve(mode, config[:models] || %{}) do
      result =
        Store.set_mode(store(), actor(scope), mode, Ecto.UUID.generate(), config[:audit_keys])

      if match?({:ok, _}, result),
        do:
          Phoenix.PubSub.broadcast(
            PauseAiCa.PubSub,
            "agent_assistant:settings",
            {:assistant_mode_changed, actor(scope)}
          )

      result
    else
      _ -> {:error, :forbidden}
    end
  end

  def conversation(scope) do
    if visible?(scope),
      do: Store.conversation(store(), actor(scope), configuration()[:audit_keys]),
      else: {:error, :forbidden}
  end

  def new_conversation(scope) do
    if visible?(scope),
      do: Store.new_conversation(store(), actor(scope), configuration()[:audit_keys]),
      else: {:error, :forbidden}
  end

  def history(scope, reference) do
    if visible?(scope),
      do: History.read(store(), actor(scope), reference, configuration()[:audit_keys]),
      else: {:error, :forbidden}
  end

  def token_usage(scope) do
    if eligible?(scope),
      do:
        Store.token_usage(
          store(),
          actor(scope),
          Date.utc_today(),
          configuration()[:daily_token_limit],
          configuration()[:max_daily_token_limit]
        ),
      else: {:error, :forbidden}
  end

  def admin_usage(scope) do
    if eligible?(scope) do
      Repo.all(
        from u in PauseAiCa.Accounts.User,
          where: u.superadmin == true and not is_nil(u.confirmed_at),
          order_by: u.email
      )
      |> Enum.map(fn user ->
        %{
          id: user.id,
          email: user.email,
          usage:
            Store.token_usage(
              store(),
              user.id,
              Date.utc_today(),
              configuration()[:daily_token_limit],
              configuration()[:max_daily_token_limit]
            )
        }
      end)
    else
      []
    end
  end

  def set_token_limit(scope, target_id, limit) do
    with true <- eligible?(scope),
         true <-
           is_integer(limit) and limit >= 0 and limit <= configuration()[:max_daily_token_limit],
         %PauseAiCa.Accounts.User{superadmin: true, confirmed_at: at} when not is_nil(at) <-
           Repo.get(PauseAiCa.Accounts.User, target_id) do
      result =
        Store.set_token_limit(
          store(),
          actor(scope),
          target_id,
          limit,
          Ecto.UUID.generate(),
          configuration()[:audit_keys]
        )

      if match?({:ok, _}, result),
        do:
          Phoenix.PubSub.broadcast(
            PauseAiCa.PubSub,
            "agent_assistant:settings",
            :assistant_settings_changed
          )

      result
    else
      _ -> {:error, :forbidden}
    end
  rescue
    _ -> {:error, :forbidden}
  end

  def run(scope, request_id, text, conversation, locale \\ "en")

  def run(scope, request_id, text, conversation, locale)
      when is_binary(text) and locale in ["en", "fr"] do
    with true <- visible?(scope),
         {:ok, mode} <- mode(scope),
         {:ok, previous} <- history(scope, conversation) do
      config =
        configuration()
        |> Keyword.put(:preference, mode)
        |> Keyword.put(:correlation_id, request_id)
        |> Keyword.put(:conversation_ref, conversation)

      identity = AcceptanceHarness.Health.payload()

      runtime = %{
        version: identity.version,
        build: identity.release_id,
        evidence: config[:feature_evidence] || %{}
      }

      catalogue =
        Catalog.for_actor(config[:features] || [], runtime, fn _ -> eligible?(scope) end)

      request = %{
        "text" => text,
        "context" => %{
          "app_version" => identity.version,
          "locale" => locale,
          "build" => identity.release_id,
          "features" => json(catalogue),
          "history" => json(Enum.take(previous, -10))
        },
        "attachments" => []
      }

      Runner.run(scope, request_id, request, __MODULE__, config)
    else
      _ -> {:error, :unavailable}
    end
  end

  def run(_, _, _, _, _), do: {:error, :unavailable}

  @impl true
  def authorize(scope, _phase, _config),
    do: if(visible?(scope), do: :ok, else: {:error, :forbidden})

  @impl true
  def record(scope, event, config) do
    event =
      event
      |> Map.put("request_id", config[:correlation_id])
      |> Map.put("runtime_policy", %{
        "bindings" => config[:bindings] || %{},
        "max_daily_token_limit" => config[:max_daily_token_limit],
        "max_turn_tokens" => config[:max_turn_tokens],
        "max_turn_cost_micros" => config[:max_turn_cost_micros]
      })

    Store.record(store(), actor(scope), Ecto.UUID.generate(), event, config[:audit_keys],
      stream: config[:conversation_ref] || "assistant"
    )
    |> persisted()
  end

  @impl true
  def alert(scope, reason, config) do
    Store.queue_alert(store(), actor(scope), Ecto.UUID.generate(), reason, config[:audit_keys],
      correlation_id: config[:correlation_id],
      severity: "warning"
    )
    |> persisted()
  end

  @impl true
  def reserve(scope, reservation, config) do
    with :ok <- authorize(scope, :reserve, config) do
      Store.reserve(store(), actor(scope), reservation, config[:audit_keys],
        max_cost_micros: config[:max_turn_cost_micros],
        daily_limit_micros: config[:daily_limit_micros],
        max_tokens: reservation.max_tokens,
        daily_token_limit: config[:daily_token_limit],
        max_daily_token_limit: config[:max_daily_token_limit]
      )
    end
  end

  @impl true
  def finish(scope, ticket, outcome, config) do
    Store.finish(store(), actor(scope), ticket.id, outcome, config[:audit_keys]) |> persisted()
  end

  defp catalogue_ready?(config) do
    identity = AcceptanceHarness.Health.payload()

    runtime = %{
      version: identity.version,
      build: identity.release_id,
      evidence: config[:feature_evidence] || %{}
    }

    features = config[:features] || []

    identity.release_id not in ["", "unknown"] and
      runtime.evidence[:build] == identity.release_id and features != [] and
      Enum.all?(features, fn feature ->
        Catalog.describe(feature, runtime).status in [:available, :new, :disabled, :unavailable]
      end)
  end

  defp persisted({:ok, _}), do: :ok
  defp persisted(_), do: {:error, :storage_unavailable}
  defp actor(%Scope{user: %{id: id}}), do: id

  defp configured?({module, options}),
    do:
      is_atom(module) and is_list(options) and is_binary(options[:api_key]) and
        byte_size(options[:api_key]) in 1..4096

  defp configured?(_), do: false

  defp valid_keys?(%{encryption: encryption, signing: signing, id: id}),
    do:
      is_binary(encryption) and byte_size(encryption) == 32 and is_binary(signing) and
        byte_size(signing) >= 32 and encryption != signing and is_binary(id) and byte_size(id) > 0

  defp valid_keys?(_), do: false

  defp json(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), json(item)} end)

  defp json(value) when is_list(value), do: Enum.map(value, &json/1)

  defp json(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp json(value), do: value
end
