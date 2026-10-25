defmodule PauseAiCa.Chat.SlackInboxWorker do
  @moduledoc "Projects at most five already-accepted inbox rows per tick. Never sends to Slack."
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_), do: {:ok, schedule()}
  @impl true
  def handle_info(:drain, timer) do
    Process.cancel_timer(timer)

    if Application.get_env(:pauseai_ca, :slack_inbox_worker_enabled, false),
      do: PauseAiCa.Chat.Slack.process_pending()

    {:noreply, schedule()}
  end

  defp schedule, do: Process.send_after(self(), :drain, 5_000)
end
