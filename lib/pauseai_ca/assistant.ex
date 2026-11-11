defmodule PauseAiCa.Assistant do
  @moduledoc "Consumer-owned assistant permissions, configuration and durable host adapter."
  @behaviour PhoenixAgentAssistant.Host
  import Ecto.Query
  alias PhoenixAgentAssistant.{Catalog, History, Modes, Runner, Store}
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.Scope

  def store, do: Store.new(Repo, "pauseai-canada")

  def configuration do
    config =
      Keyword.merge(
        [
          daily_token_limit: 100_000,
          max_daily_token_limit: 1_000_000,
          max_turn_tokens: 65_536,
          max_output_tokens: 4096
        ],
        Application.get_env(:pauseai_ca, :agent_assistant, [])
      )

    config = with_feature_evidence(config)
    instructions = instruction_snapshot()
    config = Keyword.put(config, :instruction_binding, Map.drop(instructions, [:source]))

    case config[:provider] do
      {module, options} when is_list(options) ->
        Keyword.put(
          config,
          :provider,
          {module, Keyword.put(options, :instructions, instructions.source)}
        )

      _ ->
        config
    end
  end

  defp instruction_snapshot do
    case PauseAiCa.Assistant.Instructions.effective() do
      {:ok, instructions} -> instructions
      _ -> %{source: "", revision: :unavailable, digest: nil}
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
    configured = Application.get_env(:pauseai_ca, :agent_assistant, [])
    config = if configured[:alert_delivery], do: configuration(), else: configured
    options = config[:alert_delivery] || []

    if operational_status(config).alerts == true and
         valid_keys?(config[:audit_keys] || %{}) do
      worker_options =
        options
        |> Keyword.put(:route_verified, true)
        |> Keyword.put(:activity_url, PauseAiCaWeb.Endpoint.url() <> "/admin/assistant/activity")

      {:ok, store(), config[:audit_keys], worker_options}
    else
      :disabled
    end
  end

  defp operational_status(config) do
    case config[:operations_adapter] do
      {module, options} when is_atom(module) and is_list(options) -> module.status(options)
      _ -> PauseAiCa.Assistant.Operations.status(config)
    end
  end

  @doc false
  def anchor_entry(entry, config) do
    case config[:operations_adapter] do
      {module, options} when is_atom(module) and is_list(options) ->
        module.confirm(entry, options)

      _ ->
        case PhoenixAgentAssistant.AnchorClient.confirm(
               Repo,
               entry.id,
               anchor_digest(entry),
               &lookup_anchor_digest(&1, config),
               config[:anchor] || []
             ) do
          {:ok, _} ->
            :ok

          _ ->
            PauseAiCa.Assistant.Operations.invalidate()
            {:error, :audit_anchor_unavailable}
        end
    end
  end

  defp lookup_anchor_digest(id, config) do
    with %PhoenixAgentAssistant.Store.AuditEntry{} = entry <-
           Repo.get(PhoenixAgentAssistant.Store.AuditEntry, id),
         {:ok, event} <-
           PhoenixAgentAssistant.Audit.open(
             entry.envelope,
             entry.stream_id,
             entry.previous,
             entry.sequence,
             config[:audit_keys]
           ),
         true <- event["namespace"] == store().namespace do
      {:ok, anchor_digest(entry)}
    else
      _ -> {:error, :invalid_audit}
    end
  end

  defp anchor_digest(entry),
    do:
      PhoenixAgentAssistant.Canonical.digest(%{
        "entry" => entry.id,
        "stream" => entry.stream_id,
        "sequence" => entry.sequence,
        "envelope" => entry.envelope["digest"]
      })

  defp anchor_actor(actor, config) do
    namespace = store().namespace

    entry =
      Repo.one(
        from(e in PhoenixAgentAssistant.Store.AuditEntry,
          join: s in PhoenixAgentAssistant.Store.Stream,
          on: e.stream_id == s.id,
          where:
            s.namespace == ^namespace and s.actor_id == ^actor and s.reference == "assistant" and
              e.sequence == s.sequence,
          limit: 1
        )
      )

    if entry, do: anchor_entry(entry, config), else: {:error, :audit_anchor_unavailable}
  end

  def eligible?(scope), do: Volunteers.superadmin?(scope)
  # Allocated users retain history access while readiness or daily headroom recovers.
  def launcher_visible?(scope),
    do: eligible?(scope) and Store.enabled?(store()) and positive_token_allocation?(scope)

  defp positive_token_allocation?(scope) do
    config = Application.get_env(:pauseai_ca, :agent_assistant, [])

    case Store.token_usage(
           store(),
           actor(scope),
           Date.utc_today(),
           Keyword.get(config, :daily_token_limit, 100_000),
           Keyword.get(config, :max_daily_token_limit, 1_000_000)
         ) do
      {:ok, %{limit: limit}} when is_integer(limit) and limit > 0 -> true
      _ -> false
    end
  end

  def visible?(scope), do: launcher_visible?(scope) and readiness() == []

  def readiness do
    config = configuration()
    keys = config[:audit_keys] || %{}
    operations = operational_status(config)

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
      {:operator_alerts, operations.alerts == true},
      {:audit_anchor, operations.audit_anchor == true},
      {:price_policy, match?({:ok, _}, PhoenixAgentAssistant.Pricing.bound(config))},
      {:feature_catalogue, catalogue_ready?(config)},
      {:instructions, config[:instruction_binding][:revision] != :unavailable}
    ]

    checks =
      if budget_guarded?(config),
        do:
          checks ++
            [
              {:spend_ledger, spend_ledger_ready?()},
              {:stage_tracking, config[:stage_tracking] == :required}
            ],
        else: checks

    checks =
      if Keyword.has_key?(config, :assistant_allocation),
        do: checks ++ [{:credit_allocation, credit_allocation_ready?(config)}],
        else: checks

    checks =
      if Keyword.has_key?(config, :pilot_budget),
        do:
          checks ++
            [
              {:pilot_budget,
               match?({:ok, _}, PhoenixAgentAssistant.FundedBudget.pilot_configuration(config))}
            ],
        else: checks

    for {name, false} <- checks, do: name
  end

  defp spend_ledger_ready? do
    %{rows: [[exists]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT to_regclass('agent_assistant_spend_entries') IS NOT NULL",
        [],
        log: false
      )

    exists
  rescue
    _ -> false
  end

  defp credit_allocation_ready?(config) do
    with {:ok, expected} when is_map(expected) <-
           PhoenixAgentAssistant.FundedBudget.expected(config),
         {:ok, %{attested?: true}} <-
           PhoenixAgentAssistant.CreditAllocation.status(
             store(),
             expected,
             DateTime.utc_now(),
             config[:audit_keys]
           ),
         do: true,
         else: (_ -> false)
  rescue
    _ -> false
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
         {:ok, _} <-
           Modes.resolve(
             mode,
             config[:models] || %{},
             Keyword.get(config, :allowed_modes, ~w(fast normal high))
           ),
         :ok <- mode_budget_allowed(scope, mode, config) do
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
    if launcher_visible?(scope),
      do: Store.conversation(store(), actor(scope), configuration()[:audit_keys]),
      else: {:error, :forbidden}
  end

  def new_conversation(scope) do
    if launcher_visible?(scope),
      do: Store.new_conversation(store(), actor(scope), configuration()[:audit_keys]),
      else: {:error, :forbidden}
  end

  def history(scope, reference) do
    if launcher_visible?(scope),
      do: History.read(store(), actor(scope), reference, configuration()[:audit_keys]),
      else: {:error, :forbidden}
  end

  defp budget_guarded?(config),
    do: Keyword.has_key?(config, :assistant_allocation) or Keyword.has_key?(config, :pilot_budget)

  defp mode_budget_allowed(scope, mode, config) do
    if budget_guarded?(config) do
      case PhoenixAgentAssistant.FundedBudget.availability(store(), actor(scope), config) do
        {:ok, %{modes: modes}} ->
          if get_in(modes, [mode, :allowed]) == true, do: :ok, else: {:error, :mode_unavailable}

        _ ->
          {:error, :mode_unavailable}
      end
    else
      :ok
    end
  end

  def token_usage(scope) do
    if eligible?(scope) do
      config = configuration()
      day = Date.utc_today()

      if budget_guarded?(config) do
        with {:ok, state} <-
               PhoenixAgentAssistant.FundedBudget.availability(store(), actor(scope), config),
             {:ok, usage} <- budget_usage(scope, config, day, state) do
          {:ok,
           usage
           |> Map.put(:mode_availability, state.modes)
           |> Map.put(:pilot, pilot_usage(state))}
        end
      else
        legacy_token_usage(scope, config, day)
      end
    else
      {:error, :forbidden}
    end
  end

  defp pilot_usage(%{pilot: pilot}) do
    pilot
    |> Map.take([:active, :accounted_micros, :remaining_micros])
    |> Map.merge(Map.take(pilot.snapshot, [:limit_micros, :starts_at, :expires_at]))
  end

  defp pilot_usage(_), do: nil

  defp budget_usage(scope, config, day, %{legacy?: true}),
    do: legacy_token_usage(scope, config, day)

  defp budget_usage(_scope, config, day, state) do
    money = state.actor_money

    {:ok,
     Map.merge(state.actor_tokens, %{
       reserved_cost_micros: money.retained_admission_micros,
       accounted_cost_micros: money.conservative_accounted_micros,
       pending_cost_micros:
         money.unresolved_stage_hold_micros + money.legacy_unobserved_hold_micros,
       remaining_cost_micros:
         max(config[:daily_limit_micros] - money.conservative_accounted_micros, 0),
       cost_limit_micros: config[:daily_limit_micros],
       allocation_active: state.shared.active,
       allocation_remaining_micros: state.shared.remaining_micros,
       max_turn_cost_micros: config[:max_turn_cost_micros],
       budget_reset_on: Date.add(day, 1)
     })}
  end

  defp legacy_token_usage(scope, config, day) do
    with {:ok, tokens} <-
           Store.token_usage(
             store(),
             actor(scope),
             day,
             config[:daily_token_limit],
             config[:max_daily_token_limit]
           ),
         {:ok, costs} <-
           Store.cost_usage(store(), actor(scope), day, config[:daily_limit_micros]) do
      {:ok,
       Map.merge(tokens, costs)
       |> Map.put(:max_turn_cost_micros, config[:max_turn_cost_micros])
       |> Map.put(:budget_reset_on, Date.add(day, 1))}
    end
  end

  def admin_usage(scope) do
    if eligible?(scope) do
      config = configuration()
      day = Date.utc_today()
      namespace = store().namespace

      current =
        Repo.all(
          from(u in PauseAiCa.Accounts.User,
            where: u.superadmin == true and not is_nil(u.confirmed_at)
          )
        )

      historical =
        Repo.all(
          from(r in PhoenixAgentAssistant.Store.Request,
            where: r.namespace == ^namespace and r.budget_day == ^day,
            distinct: true,
            select: r.actor_id
          )
        )

      ids = Enum.uniq(Enum.map(current, & &1.id) ++ historical)
      user_ids = for id <- ids, {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid

      users =
        Repo.all(from(u in PauseAiCa.Accounts.User, where: u.id in ^user_ids))
        |> Map.new(&{&1.id, &1})

      current_ids = MapSet.new(Enum.map(current, & &1.id))

      Enum.map(ids, fn id ->
        user =
          case Ecto.UUID.cast(id) do
            {:ok, uuid} -> users[uuid]
            _ -> nil
          end

        %{
          id: id,
          email: user && user.email,
          current_admin: MapSet.member?(current_ids, id),
          usage:
            Store.token_usage(
              store(),
              id,
              day,
              config[:daily_token_limit],
              config[:max_daily_token_limit]
            ),
          spend: read_spend_usage(id, config, day)
        }
      end)
      |> Enum.sort_by(&{is_nil(&1.email), &1.email || &1.id})
    else
      []
    end
  end

  @doc "Read-only USD service observations for authorized administrators; never an account/credit balance."
  def spend_usage(scope, target_actor \\ nil) do
    if eligible?(scope) do
      read_spend_usage(target_actor || actor(scope), configuration(), Date.utc_today())
    else
      {:error, :forbidden}
    end
  end

  defp read_spend_usage(target_actor, config, day) do
    if config[:stage_tracking] == :required do
      with {:ok, summary} <-
             PhoenixAgentAssistant.SpendLedger.summary(
               store(),
               target_actor,
               day,
               config[:audit_keys]
             ),
           do: {:ok, Map.put(summary, :accounting, :ledger)}
    else
      with {:ok, costs} <-
             Store.cost_usage(store(), target_actor, day, config[:daily_limit_micros]),
           do: {:ok, Map.put(costs, :accounting, :reservations_only)}
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

  def run(scope, request_id, text, conversation, locale \\ "en"),
    do: run(scope, request_id, text, conversation, locale, [])

  def run(scope, request_id, text, conversation, locale, options)
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
          "history" => []
        },
        "attachments" => []
      }

      messages =
        Enum.map(previous, fn message -> %{"role" => message.role, "text" => message.text} end)

      guided = Keyword.get(options, :guided_mode, false)

      with {:ok, request} <- guided_request(scope, request, locale, guided),
           {:ok, request} <- PhoenixAgentAssistant.Context.with_history(request, messages) do
        Runner.run(scope, request_id, request, __MODULE__, config)
      else
        _ -> {:error, :unavailable}
      end
    else
      _ -> {:error, :unavailable}
    end
  end

  def run(_, _, _, _, _, _), do: {:error, :unavailable}

  defp guided_request(_scope, request, _locale, false), do: {:ok, request}

  defp guided_request(scope, request, locale, true) do
    with {:ok, knowledge} <- PauseAiCa.Assistant.GuidedMode.context(scope, locale) do
      request =
        request
        |> put_in(["context", "guided_mode"], knowledge)
        |> put_in(
          ["context", "canadian_references"],
          PauseAiCa.Assistant.CanadianReferences.context()
        )

      {:ok, request}
    end
  end

  defp guided_request(_, _, _, _), do: {:error, :unavailable}

  @impl true
  def authorize(scope, _phase, admitted) do
    with true <- visible?(scope),
         current = configuration(),
         true <- execution_snapshot(admitted) == execution_snapshot(current),
         true <- funded_snapshot_current?(admitted, current) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  rescue
    _ -> {:error, :forbidden}
  end

  defp execution_snapshot(config) do
    # Compare only trusted execution configuration, in memory. Runtime readiness
    # results are not config entries. Per-request context and the newly-created
    # reservation closure do not change the authorized policy/paid routes.
    [
      daily_token_limit: 100_000,
      max_daily_token_limit: 1_000_000,
      max_turn_tokens: 65_536,
      max_output_tokens: 4096
    ]
    |> Keyword.merge(config)
    |> Keyword.put_new_lazy(:instruction_binding, fn ->
      Map.drop(instruction_snapshot(), [:source])
    end)
    |> Keyword.drop([:preference, :correlation_id, :conversation_ref, :spend_reservation_prepare])
    |> Map.new()
    |> Map.put(:provider, provider_snapshot(config))
  end

  defp provider_snapshot(config) do
    case config[:provider] do
      {module, options} when is_atom(module) and is_list(options) ->
        {module,
         options
         |> Keyword.put_new_lazy(:instructions, fn -> instruction_snapshot().source end)
         |> Map.new()}

      _ ->
        :invalid
    end
  end

  defp funded_snapshot_current?(admitted, current) do
    guarded = Keyword.has_key?(admitted, :assistant_allocation)

    if guarded == Keyword.has_key?(current, :assistant_allocation) do
      if guarded do
        with {:ok, expected} when is_map(expected) <-
               PhoenixAgentAssistant.FundedBudget.expected(admitted),
             {:ok, ^expected} <- PhoenixAgentAssistant.FundedBudget.expected(current),
             {:ok, %{attested?: true}} <-
               PhoenixAgentAssistant.CreditAllocation.status(
                 store(),
                 expected,
                 DateTime.utc_now(),
                 admitted[:audit_keys]
               ) do
          true
        else
          _ -> false
        end
      else
        true
      end
    else
      false
    end
  end

  @impl true
  def record(scope, event, config) do
    event =
      event
      |> Map.put("request_id", config[:correlation_id])
      |> Map.put("runtime_policy", %{
        "instructions" => json(config[:instruction_binding]),
        "bindings" => config[:bindings] || %{},
        "max_daily_token_limit" => config[:max_daily_token_limit],
        "max_turn_tokens" => config[:max_turn_tokens],
        "max_turn_cost_micros" => config[:max_turn_cost_micros]
      })

    with {:ok, %{entry: entry}} <-
           Store.record(store(), actor(scope), Ecto.UUID.generate(), event, config[:audit_keys],
             stream: config[:conversation_ref] || "assistant"
           ),
         :ok <- anchor_entry(entry, config),
         do: :ok
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
      if config[:stage_tracking] == :required do
        with {:ok, state} <-
               PhoenixAgentAssistant.FundedBudget.availability(store(), actor(scope), config),
             true <- get_in(state, [:modes, reservation.mode, :allowed]) == true,
             :ok <- anchor_funding_state(state, config),
             {:ok, slots} <- PauseAiCa.Assistant.SpendTracking.slots(reservation, config),
             {:ok, prepare} <-
               PhoenixAgentAssistant.FundedBudget.prepare(
                 store(),
                 actor(scope),
                 slots,
                 config,
                 state.proof
               ) do
          PauseAiCa.Assistant.SpendTracking.reserve(
            store(),
            actor(scope),
            reservation,
            Keyword.put(config, :spend_reservation_prepare, prepare)
          )
        else
          false -> {:error, :mode_unavailable}
          {:error, _} = error -> error
          _ -> {:error, :funded_budget_unavailable}
        end
      else
        result =
          Store.reserve(store(), actor(scope), reservation, config[:audit_keys],
            max_cost_micros: config[:max_turn_cost_micros],
            daily_limit_micros: config[:daily_limit_micros],
            max_tokens: reservation.max_tokens,
            daily_token_limit: config[:daily_token_limit],
            max_daily_token_limit: config[:max_daily_token_limit]
          )

        with {:ok, ticket} <- result, :ok <- anchor_actor(actor(scope), config), do: {:ok, ticket}
      end
    end
  end

  defp anchor_funding_state(%{legacy?: true}, _), do: :ok

  defp anchor_funding_state(%{entry: %PhoenixAgentAssistant.Store.AuditEntry{} = entry}, config),
    do: anchor_entry(entry, config)

  defp anchor_funding_state(_, _), do: {:error, :funded_budget_unavailable}

  @impl true
  def observe_stage(scope, ticket, purpose, event, config) do
    with :ok <- authorize(scope, :spend_observation, config) do
      PauseAiCa.Assistant.SpendTracking.observe(
        store(),
        actor(scope),
        ticket,
        purpose,
        event,
        config
      )
    end
  end

  @impl true
  def finish(scope, ticket, outcome, config) do
    with {:ok, _} <- Store.finish(store(), actor(scope), ticket.id, outcome, config[:audit_keys]),
         :ok <- anchor_actor(actor(scope), config),
         do: :ok
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
