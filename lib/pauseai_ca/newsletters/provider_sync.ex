defmodule PauseAiCa.Newsletters.ProviderSync do
  @moduledoc "Persisted, bounded global history cursor with overlapping recent windows and visible failures."
  import Ecto.Query
  alias PauseAiCa.Repo

  alias PauseAiCa.Newsletters.{
    Batch,
    Delivery,
    ProviderHistory,
    ProviderReconciliation,
    ProviderSyncState
  }

  @id "brevo-newsletters"
  @lookback_days 3

  def status, do: Repo.get(ProviderSyncState, @id)

  @doc "One bounded reconciliation pass. The supervised worker separately enforces production-only enablement."
  def run(fetcher \\ &ProviderHistory.fetch_page/1, now \\ DateTime.utc_now()) do
    result =
      Repo.transaction(
        fn ->
          %{rows: [[locked]]} =
            Ecto.Adapters.SQL.query!(
              Repo,
              "SELECT pg_try_advisory_xact_lock(hashtext('newsletter-provider-poll'))",
              []
            )

          if not locked, do: Repo.rollback(:busy)
          Repo.insert!(%ProviderSyncState{id: @id}, on_conflict: :nothing)
          state = Repo.get!(ProviderSyncState, @id)
          {from, until, offset, full_scan} = window(state, now)

          case ProviderHistory.pages(from, until, offset, fetcher) do
            {:ok, page} ->
              case ProviderReconciliation.reconcile(page.events) do
                {:ok, counts} ->
                  totals =
                    if state.partial,
                      do: Map.merge(state.counts, counts, fn _, a, b -> a + b end),
                      else: counts

                  Repo.update!(
                    Ecto.Changeset.change(state,
                      window_start: from,
                      window_end: until,
                      offset: page.offset,
                      partial: page.partial,
                      full_scan: full_scan,
                      last_full_scan_at:
                        if(full_scan and not page.partial, do: now, else: state.last_full_scan_at),
                      cursor_at: if(page.partial, do: state.cursor_at, else: now),
                      last_attempt_at: now,
                      last_success_at: now,
                      last_error: if(totals["invalid"] > 0, do: "invalid_events", else: nil),
                      counts: totals
                    )
                  )

                {:error, reason} ->
                  Repo.rollback(reason)
              end

            {:error, reason} ->
              Repo.update!(
                Ecto.Changeset.change(state, last_attempt_at: now, last_error: error_code(reason))
              )
          end
        end,
        timeout: 60_000
      )

    result
  rescue
    _ ->
      record_failure(now)
      {:error, :unavailable}
  end

  defp record_failure(now) do
    Repo.transaction(fn ->
      %{rows: [[locked]]} =
        Ecto.Adapters.SQL.query!(
          Repo,
          "SELECT pg_try_advisory_xact_lock(hashtext('newsletter-provider-poll'))",
          []
        )

      if locked do
        Repo.insert!(%ProviderSyncState{id: @id}, on_conflict: :nothing)
        state = Repo.get!(ProviderSyncState, @id)

        if is_nil(state.last_attempt_at) or DateTime.compare(state.last_attempt_at, now) != :gt do
          state
          |> Ecto.Changeset.change(last_attempt_at: now, last_error: "unavailable")
          |> Repo.update!()
        end
      end
    end)
  rescue
    _ -> :unavailable
  end

  defp window(
         %{
           partial: true,
           window_start: %Date{} = from,
           window_end: %Date{} = until,
           offset: offset,
           full_scan: full_scan
         },
         _
       ),
       do: {from, until, offset, full_scan}

  defp window(state, now) do
    today = DateTime.to_date(now)
    oldest = Date.add(today, -89)

    full_scan =
      is_nil(state.last_full_scan_at) or DateTime.diff(now, state.last_full_scan_at) >= 86_400

    start =
      if state.cursor_at && not full_scan do
        Date.add(DateTime.to_date(state.cursor_at), -@lookback_days)
      else
        Repo.one(
          from d in Delivery,
            join: b in Batch,
            on: b.id == d.batch_id,
            where: b.delivery_environment == "production" and not is_nil(d.attempted_at),
            select: min(d.attempted_at)
        )
        |> case do
          nil -> today
          at -> DateTime.to_date(at)
        end
      end

    {Enum.max([start, oldest], Date), today, 0, full_scan}
  end

  defp error_code(reason)
       when reason in [
              :rate_limited,
              :not_configured,
              :invalid_response,
              :unavailable,
              :invalid_events,
              :environment_blocked
            ],
       do: Atom.to_string(reason)

  defp error_code(_), do: "unavailable"
end
