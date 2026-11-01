defmodule PauseAiCa.OutreachProvider do
  @moduledoc "Bounded consumer processing; raw receipts stay durable when processing fails."
  use GenServer
  require Logger
  alias PauseAiCa.{Outreach, OutreachAttachments, OutreachNotifier}

  def start_link(opts) do
    if Application.get_env(:pauseai_ca, :outreach_worker_enabled, false),
      do: GenServer.start_link(__MODULE__, opts, name: __MODULE__),
      else: :ignore
  end

  def process_once do
    results =
      Enum.map(Outreach.pending_receipts(10), fn receipt ->
        result =
          try do
            with {:ok, archived} <- Outreach.process_receipt(receipt.id),
                 :ok <- OutreachAttachments.ensure(receipt),
                 {:ok, _} <- Outreach.complete_attachments(receipt.id) do
              {:ok, archived}
            end
          rescue
            _ -> {:error, :processing_failed}
          end

        case result do
          {:error, reason} ->
            category = if is_atom(reason), do: reason, else: :processing_failed
            Outreach.record_processing_failure(receipt.id, category)
            {:error, category}

          result ->
            result
        end
      end)

    %{
      receipts: results,
      notifications: Outreach.dispatch_notifications(&OutreachNotifier.deliver/1)
    }
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:process, state) do
    try do
      process_once()
    rescue
      _ -> Logger.warning("Outreach processing unavailable; durable receipts retained")
    after
      schedule()
    end

    {:noreply, state}
  end

  defp schedule do
    Process.send_after(self(), :process, 15_000)
  end
end
