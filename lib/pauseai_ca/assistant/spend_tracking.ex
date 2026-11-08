defmodule PauseAiCa.Assistant.SpendTracking do
  @moduledoc "Consumer-owned frozen spend plans and independently anchored stage observations."
  alias PauseAiCa.Assistant
  alias PhoenixAgentAssistant.{Canonical, Modes, Pricing, SpendCost, SpendLedger, Store}
  alias PhoenixAgentAssistant.Store.{AuditEntry, Stream}

  @doc "Build all five slots from the exact server model/rate snapshot admitted by Runner."
  def slots(reservation, config) when is_map(reservation) and is_list(config) do
    with true <- Keyword.get(config, :stage_tracking) == :required,
         {:ok, split} <- Pricing.stage_bounds(config),
         {:ok, mode} <-
           Modes.resolve(
             reservation.mode,
             config[:models],
             Keyword.get(config, :allowed_modes, ~w(fast normal high))
           ),
         true <-
           mode.model == reservation.model and
             reservation.max_output_tokens == config[:max_output_tokens],
         true <- reservation.max_cost_micros == config[:max_turn_cost_micros],
         true <-
           is_integer(reservation.max_tokens) and
             reservation.max_tokens >= reservation.max_output_tokens and
             reservation.max_tokens <= config[:max_turn_tokens],
         {:ok, generation} <- generation_provider(config[:provider]),
         {:ok, moderation} <- moderation_model(get_in(config, [:safety, :moderation])),
         {:ok, jev} <- jev_model(get_in(config, [:safety, :jev])),
         policy = config[:pricing],
         rates = policy["models"][mode.model] do
      slots = [
        slot(
          "generation",
          generation,
          mode.model,
          split.generation_micros,
          policy,
          rates["input_micros"],
          rates["output_micros"]
        ),
        slot("input_moderation", "openai", moderation, 0, policy, 0, 0),
        slot(
          "input_jev",
          "jev",
          jev,
          split.jev_review_micros,
          policy,
          policy["jev_input_micros"],
          0
        ),
        slot("output_moderation", "openai", moderation, 0, policy, 0, 0),
        slot(
          "output_jev",
          "jev",
          jev,
          split.jev_review_micros,
          policy,
          policy["jev_input_micros"],
          0
        )
      ]

      if Enum.all?(slots, &match?({:ok, _}, SpendCost.slot(&1))) and
           Enum.sum(Enum.map(slots, & &1["max_cost_micros"])) == reservation.max_cost_micros,
         do: {:ok, slots},
         else: {:error, :invalid_spend_plan}
    else
      _ -> {:error, :invalid_spend_plan}
    end
  rescue
    _ -> {:error, :invalid_spend_plan}
  end

  def slots(_, _), do: {:error, :invalid_spend_plan}

  @doc "Reserve first; a partial plan/anchor failure keeps admission holds and never returns an executable ticket."
  def reserve(store, actor, reservation, config) do
    with {:ok, slots} <- slots(reservation, config),
         {:ok, ticket} <-
           Store.reserve_with_plan(
             store,
             actor,
             reservation,
             config[:audit_keys],
             [
               money_accounting: :spend_ledger,
               max_cost_micros: config[:max_turn_cost_micros],
               daily_limit_micros: config[:daily_limit_micros],
               max_tokens: reservation.max_tokens,
               daily_token_limit: config[:daily_token_limit],
               max_daily_token_limit: Keyword.get(config, :max_daily_token_limit, 1_000_000_000)
             ],
             Keyword.get(config, :spend_reservation_prepare, fn attrs ->
               %{attrs: attrs, event: %{}, persist: fn _, _ -> :ok end}
             end)
           ),
         :ok <- anchor(store, actor, ticket.audit_ref, config),
         {:ok, entries} <-
           SpendLedger.plan(
             store,
             actor,
             ticket.id,
             slots,
             Canonical.digest(%{"request" => ticket.id, "plan" => slots}),
             config[:audit_keys]
           ),
         :ok <- anchor_all(store, actor, entries, config) do
      {:ok, ticket}
    end
  rescue
    _ -> {:error, :spend_tracking_unavailable}
  end

  @doc "Persist and anchor exactly the observation returned by the authenticated ledger, including idempotent replays."
  def observe(store, actor, ticket, purpose, event, config) do
    with true <- config[:stage_tracking] == :required and purpose in SpendCost.slots(),
         true <- is_map(event) and Enum.sort(Map.keys(event)) == ~w(billing state usage),
         digest =
           Canonical.digest(%{"request" => ticket.id, "purpose" => purpose, "event" => event}),
         observation = Map.put(event, "evidence_ref", digest),
         {:ok, entry} <-
           SpendLedger.record(
             store,
             actor,
             ticket.id,
             purpose,
             digest,
             observation,
             config[:audit_keys]
           ),
         :ok <- anchor(store, actor, entry.audit_ref, config) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_spend_observation}
    end
  rescue
    _ -> {:error, :spend_tracking_unavailable}
  end

  defp slot(purpose, provider, model, maximum, policy, input, output),
    do: %{
      "purpose" => purpose,
      "provider" => provider,
      "model" => model,
      "max_cost_micros" => maximum,
      "rate_policy_id" => policy["policy_id"],
      "input_micros" => input,
      "output_micros" => output
    }

  defp generation_provider({PhoenixAgentAssistant.Anthropic, _}), do: {:ok, "anthropic"}
  defp generation_provider({PhoenixAgentAssistant.OpenAI, _}), do: {:ok, "openai"}
  defp generation_provider({PhoenixAgentAssistant.OpenRouter, _}), do: {:ok, "openrouter"}
  defp generation_provider(_), do: {:error, :invalid_spend_provider}

  defp moderation_model({PhoenixAgentAssistant.Safety.OpenAIModeration, options})
       when is_list(options),
       do: {:ok, Keyword.get(options, :model, "omni-moderation-latest")}

  defp moderation_model(_), do: {:error, :invalid_spend_provider}

  defp jev_model({module, options})
       when module in [PhoenixAgentAssistant.Safety.Jev, PhoenixAgentAssistant.Safety.JevGateway] and
              is_list(options),
       do: {:ok, options[:model]}

  defp jev_model(_), do: {:error, :invalid_spend_provider}

  defp anchor_all(store, actor, entries, config) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case anchor(store, actor, entry.audit_ref, config) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp anchor(store, actor, id, config) do
    with %AuditEntry{} = entry <- store.repo.get(AuditEntry, id),
         %Stream{} = stream <- store.repo.get(Stream, entry.stream_id),
         true <- stream.namespace == store.namespace and stream.actor_id == actor,
         :ok <- Assistant.anchor_entry(entry, config) do
      :ok
    else
      _ -> {:error, :audit_anchor_unavailable}
    end
  rescue
    _ -> {:error, :audit_anchor_unavailable}
  end
end
