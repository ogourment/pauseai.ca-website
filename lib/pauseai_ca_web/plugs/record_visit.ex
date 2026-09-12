defmodule PauseAiCaWeb.Plugs.RecordVisit do
  @moduledoc """
  Counts a CSRF-protected browser POST once per signed session and UTC day.

  Public GET requests never increment this counter. JavaScript-capable bots
  can still emit signals; this is not a verified-human or unique-person count.

  Only the daily aggregate is stored. The application does not retain an IP,
  user agent, path, account, or other visitor identifier.
  """

  import Plug.Conn

  require Logger

  alias PauseAiCa.Engagement

  # Never reuse the old GET counter's marker: old cookies must not suppress
  # their first signal after the measurement cutover.
  @session_key :browser_visit_recorded_on

  def init(opts), do: opts

  def call(%Plug.Conn{method: "POST", request_path: "/engagement/visits"} = conn, _opts) do
    today = Date.utc_today()
    marker = Date.to_iso8601(today)

    if disabled?(conn) or superadmin?(conn) or
         get_session(conn, @session_key) == marker do
      conn
    else
      record(conn, today, marker)
    end
  end

  def call(conn, _opts), do: conn

  defp superadmin?(conn) do
    case conn.assigns[:current_scope] do
      %{user: %{superadmin: true}} -> true
      _ -> false
    end
  end

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
