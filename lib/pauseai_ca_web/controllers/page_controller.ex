defmodule PauseAiCaWeb.PageController do
  use PauseAiCaWeb, :controller

  def index(conn, _params), do: render_home(conn, "en")
  def en(conn, _params), do: render_home(conn, "en")
  def fr(conn, _params), do: render_home(conn, "fr")

  defp render_home(conn, locale) do
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    render(conn, :home,
      locale: locale,
      page_title: if(locale == "fr", do: "Comprendre et agir", else: "Understand and act")
    )
  end
end
