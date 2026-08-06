defmodule PauseAiCaWeb.Plugs.RecordVisit do
  @moduledoc """
  Counts one first-party visit per browser and UTC day.

  Only the daily aggregate is stored. The application does not retain an IP,
  user agent, path, account, or other visitor identifier.
  """

  import Plug.Conn

  require Logger

  alias PauseAiCa.Engagement

  @session_key :visit_recorded_on
  @excluded_prefixes ["/admin", "/dev", "/health"]

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    today = Date.utc_today()
    marker = Date.to_iso8601(today)

    if disabled?(conn) or excluded?(conn.request_path) or
         get_session(conn, @session_key) == marker do
      conn
    else
      record(conn, today, marker)
    end
  end

  def call(conn, _opts), do: conn

  defp excluded?(path),
    do: Enum.any?(@excluded_prefixes, &String.starts_with?(path, &1))

  defp disabled?(conn) do
    not Application.get_env(:pauseai_ca, :record_visits, true) and
      conn.private[:record_visits] != true
  end

  defp record(conn, today, marker) do
    Engagement.record_visit(today)
    put_session(conn, @session_key, marker)
  rescue
    error ->
      Logger.warning("Could not record aggregate visit: #{Exception.message(error)}")
      conn
  end
end
