defmodule PauseAiCaWeb.VolunteerProfileRedirectController do
  use PauseAiCaWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: if(conn.assigns.locale == "fr", do: ~p"/fr/profil", else: ~p"/en/profile"))
  end
end
