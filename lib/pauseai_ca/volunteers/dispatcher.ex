defmodule PauseAiCa.Volunteers.Dispatcher do
  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if Application.get_env(:pauseai_ca, :volunteer_dispatcher, true),
      do: Process.send_after(self(), :dispatch, 5_000)

    {:ok, nil}
  end

  @impl true
  def handle_info(:dispatch, state) do
    try do
      PauseAiCa.Volunteers.dispatch_pending()
    rescue
      _ -> Logger.error("volunteer_invitation queue processing failed; queued records retained")
    end

    Process.send_after(self(), :dispatch, 30_000)
    {:noreply, state}
  end
end
