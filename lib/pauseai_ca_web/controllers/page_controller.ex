defmodule PauseAiCaWeb.PageController do
  use PauseAiCaWeb, :controller

  def index(conn, _params), do: render_home(conn, "en")
  def en(conn, _params), do: render_home(conn, "en")
  def fr(conn, _params), do: render_home(conn, "fr")
  def strategy_en(conn, _params), do: render_content(conn, :strategy, "en", "Our strategy")
  def strategy_fr(conn, _params), do: render_content(conn, :strategy, "fr", "Notre stratégie")
  def about_en(conn, _params), do: render_content(conn, :about, "en", "Who we are")
  def about_fr(conn, _params), do: render_content(conn, :about, "fr", "Qui sommes-nous?")
  def privacy_en(conn, _params), do: render_content(conn, :privacy, "en", "Privacy policy")

  def privacy_fr(conn, _params),
    do: render_content(conn, :privacy, "fr", "Politique de confidentialité")

  defp render_home(conn, locale) do
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    render(conn, :home,
      locale: locale,
      page_title: if(locale == "fr", do: "Comprendre et agir", else: "Understand and act")
    )
  end

  defp render_content(conn, template, locale, title) do
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    render(conn, template, locale: locale, page_title: title)
  end
end
