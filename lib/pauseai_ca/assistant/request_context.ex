defmodule PauseAiCa.Assistant.RequestContext do
  @moduledoc "Keeps model context within the configured turn ceiling without changing the question or spending policy."
  alias PhoenixAgentAssistant.{Context, Modes}

  def catalogue(features, ids \\ :all) do
    # The request already carries build/version. Test IDs belong to audit evidence,
    # rather than the model's coaching context. Availability and controls remain.
    features
    |> Enum.filter(&(ids == :all or &1.id in ids))
    |> Enum.map(&Map.drop(&1, [:build, :app_version, :scenarios]))
  end

  def prepare(request, messages, config, mode) do
    with {:ok, provider_mode} <-
           Modes.resolve(
             mode,
             config[:models] || %{},
             config[:allowed_modes] || ~w(fast normal high)
           ),
         ceiling when is_integer(ceiling) and ceiling > 0 <- config[:max_turn_tokens],
         output when is_integer(output) and output in 1..4096 <- config[:max_output_tokens],
         {provider, options} <- config[:provider],
         {:ok, bound} when is_integer(bound) and bound > 0 <-
           provider.input_token_bound(request, provider_mode, options) do
      Context.with_history(request, messages, 40_000, fn candidate ->
        case provider.input_token_bound(candidate, provider_mode, options) do
          {:ok, input} when is_integer(input) and input > 0 -> input + output <= ceiling
          _ -> false
        end
      end)
    else
      _ -> {:error, :token_limit_unavailable}
    end
  rescue
    _ -> {:error, :token_limit_unavailable}
  end
end
