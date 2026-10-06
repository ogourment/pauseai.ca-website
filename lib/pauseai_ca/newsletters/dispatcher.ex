defmodule PauseAiCa.Newsletters.Dispatcher do
  use GenServer
  require Logger
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(_) do
    if Application.get_env(:pauseai_ca, :newsletter_dispatcher, false),
      do: Process.send_after(self(), :dispatch, 5000)

    {:ok, nil}
  end

  def handle_info(:dispatch, state) do
    try do
      PauseAiCa.Newsletters.Batches.dispatch_pending()
    rescue
      _ ->
        Logger.error("newsletter delivery interrupted; durable reservations retained for review")
    end

    Process.send_after(self(), :dispatch, 30_000)
    {:noreply, state}
  end
end
