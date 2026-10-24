defmodule PauseAiCa.Health do
  @moduledoc "Readiness includes a bounded query against the application database."

  def check(query \\ &database_query/0) do
    payload = AcceptanceHarness.Health.payload()

    if available?(query) do
      {:ok, Map.put(payload, :database, "ok")}
    else
      {:service_unavailable,
       Map.merge(payload, %{status: "unavailable", database: "unavailable"})}
    end
  end

  defp database_query do
    PauseAiCa.Repo.query("SELECT 1", [],
      timeout: 500,
      pool_timeout: 500,
      queue: true,
      log: false
    )
  end

  defp available?(query) do
    match?({:ok, %{rows: [[1]]}}, query.())
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end
end
