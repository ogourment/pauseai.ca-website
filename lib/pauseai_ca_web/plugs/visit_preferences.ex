defmodule PauseAiCaWeb.Plugs.VisitPreferences do
  @moduledoc "A signed, domain-scoped browser opt-out for aggregate visit counts."
  import Plug.Conn
  @cookie "_pauseai_exclude_visits"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn, signed: [@cookie])
    excluded? = conn.cookies[@cookie] == "true"

    conn
    |> assign(:exclude_browser_visits, excluded?)
    |> put_session(:exclude_browser_visits, excluded?)
  end

  def set(conn, true) do
    put_resp_cookie(conn, @cookie, "true",
      sign: true,
      http_only: true,
      secure: conn.scheme == :https,
      same_site: "Lax",
      max_age: 365 * 24 * 60 * 60
    )
  end

  def set(conn, false), do: delete_resp_cookie(conn, @cookie)
end
