defmodule PauseAiCa.Chat.SlackPolicy do
  @moduledoc "Explicit website audiences for configured Slack channels; provider checks remain mandatory."
  def allowed?(scope, channel, action) when action in [:read, :post] do
    policies = Application.get_env(:pauseai_ca, :slack, %{})[:channel_audiences] || %{}

    case policies[channel] do
      "linked_accounts" ->
        not is_nil(scope.user.confirmed_at)

      %{"group_id" => id} ->
        # Admission is supplied by the consumer's group feature when installed.
        if Code.ensure_loaded?(PauseAiCa.Incubators) and
             function_exported?(PauseAiCa.Incubators, :mine, 2) do
          case apply(PauseAiCa.Incubators, :mine, [scope, id]) do
            {:ok, %{status: status, external_removal_pending: false}}
            when status in ["approved", "admitted"] ->
              true

            _ ->
              false
          end
        else
          false
        end

      _ ->
        false
    end
  end

  def allowed?(_, _, _), do: false
end
