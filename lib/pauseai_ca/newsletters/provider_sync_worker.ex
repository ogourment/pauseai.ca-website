defmodule PauseAiCa.Newsletters.ProviderSyncWorker do
  @moduledoc "A separate read-only production history worker; never dispatches or resends mail."
  use GenServer
  require Logger
  @interval :timer.minutes(15)
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def enabled? do
    PauseAiCa.MailSafety.environment() == :production and
      Application.get_env(:pauseai_ca, :newsletter_provider_sync_enabled, false)
  end

  @impl true
  def init(_) do
    if enabled?(), do: Process.send_after(self(), :reconcile, @interval)
    {:ok, nil}
  end

  @impl true
  def handle_info(:reconcile, state) do
    if enabled?() do
      case PauseAiCa.Newsletters.ProviderSync.run() do
        {:ok, %{last_error: error}} when not is_nil(error) ->
          Logger.error(
            "Newsletter provider reconciliation needs attention; inspect /manage/mail/results"
          )

        {:error, _} ->
          Logger.error(
            "Newsletter provider reconciliation failed; inspect synchronization status"
          )

        _ ->
          :ok
      end

      Process.send_after(self(), :reconcile, @interval)
    end

    {:noreply, state}
  end
end
