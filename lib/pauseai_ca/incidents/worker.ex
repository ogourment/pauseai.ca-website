defmodule PauseAiCa.Incidents.Worker do
  use GenServer
  alias PauseAiCa.Incidents
  alias PauseAiCa.Incidents.Delivery

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  @impl true
  def init(_) do
    :ets.new(:pauseai_incident_buffer, [:named_table, :public, :set, write_concurrency: true])
    :ets.new(:pauseai_browser_rate, [:named_table, :public, :set, write_concurrency: true])

    if Incidents.environment() in ["production", "staging"] do
      :logger.add_handler(:pauseai_incidents, PauseAiCa.Incidents.LogHandler, %{level: :error})
      attach_exceptions()
      schedule()
    end

    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.put(:pauseai_reporting, true)

    try do
      Incidents.flush()
      Incidents.prune()

      case Application.get_env(:pauseai_ca, :ops_telegram) do
        {token, chat} -> Delivery.dispatch(&Delivery.telegram(token, chat, &1))
        _ -> :disabled
      end
    rescue
      # Never recursively report database or Telegram transport problems here.
      _ -> :unavailable
    after
      schedule()
    end

    {:noreply, state}
  end

  defp attach_exceptions do
    events = [
      [:phoenix, :router_dispatch, :exception],
      [:phoenix, :live_view, :mount, :exception],
      [:phoenix, :live_view, :handle_event, :exception],
      [:phoenix, :live_view, :render, :exception],
      [:phoenix, :live_component, :handle_event, :exception]
    ]

    :telemetry.attach_many(__MODULE__, events, &__MODULE__.exception/4, nil)
  end

  def exception(_event, _measurements, %{reason: reason, stacktrace: stack}, _) do
    PauseAiCa.Incidents.LogHandler.log(%{meta: %{crash_reason: {reason, stack}}}, nil)
  end

  def exception(_, _, _, _), do: :ok

  defp schedule, do: Process.send_after(self(), :tick, 15_000)
end
