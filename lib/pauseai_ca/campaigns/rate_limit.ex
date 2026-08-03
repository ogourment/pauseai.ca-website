defmodule PauseAiCa.Campaigns.RateLimit do
  @moduledoc """
  A fixed-window counter for actions that send email.

  Deliberately small: an ETS table of counters, swept on read. There is one
  application node, the volumes involved are tiny, and a limiter nobody
  understands is worse than none.

  Two ceilings apply to every send. A per-sender one stops a single visitor
  bombarding an office, and a global one caps the damage if the first is
  circumvented — a burst from many addresses would otherwise be signed by our
  own DKIM key.
  """

  use GenServer

  @table :campaign_rate_limit
  @global_key {:global, :letters}

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @doc """
  Records one send for `key`, or refuses.

  Returns `:ok`, or `{:error, :rate_limited}` when either the per-sender or the
  global ceiling for the current window is already reached.
  """
  @spec check(String.t()) :: :ok | {:error, :rate_limited}
  def check(key) do
    now = System.system_time(:second)

    with :ok <- take({:sender, key}, per_sender_limit(), window(), now),
         :ok <- take(@global_key, global_limit(), window(), now) do
      :ok
    end
  end

  @doc "Forgets every counter. Test support."
  @spec reset() :: :ok
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  defp take(key, limit, window, now) do
    window_start = div(now, window) * window

    count =
      case :ets.lookup(@table, key) do
        [{^key, ^window_start, count}] -> count
        # Either unseen or from an expired window; either way, start again.
        _stale -> 0
      end

    if count >= limit do
      {:error, :rate_limited}
    else
      :ets.insert(@table, {key, window_start, count + 1})
      :ok
    end
  end

  defp window, do: Application.get_env(:pauseai_ca, :campaign_rate_window, 3_600)
  defp per_sender_limit, do: Application.get_env(:pauseai_ca, :campaign_rate_per_sender, 3)
  defp global_limit, do: Application.get_env(:pauseai_ca, :campaign_rate_global, 200)
end
