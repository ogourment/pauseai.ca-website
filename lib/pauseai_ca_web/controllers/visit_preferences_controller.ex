defmodule PauseAiCaWeb.VisitPreferencesController do
  use PauseAiCaWeb, :controller

  def update(conn, %{"excluded" => value}) when value in ["true", "false"] do
    conn
    |> PauseAiCaWeb.Plugs.VisitPreferences.set(value == "true")
    |> redirect(to: ~p"/admin/dashboard")
  end

  def update(conn, _), do: send_resp(conn, :bad_request, "Invalid preference")
end
