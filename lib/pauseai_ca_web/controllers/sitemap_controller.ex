defmodule PauseAiCaWeb.SitemapController do
  use PauseAiCaWeb, :controller

  def index(conn, _params) do
    locale = PauseAiCaWeb.Site.default_locale(conn.host)
    entries = Enum.filter(PauseAiCaWeb.SEO.entries(), &String.starts_with?(&1.path, "/#{locale}"))

    body =
      entries
      |> Enum.map(fn entry ->
        %{
          url: PauseAiCaWeb.Site.url(locale, entry.path),
          alternates: PauseAiCaWeb.SEO.alternates(entry)
        }
      end)
      |> PhoenixAppShell.SEO.sitemap()

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header(
      "x-robots-tag",
      if(PauseAiCa.Environment.badged?(), do: "noindex", else: "all")
    )
    |> send_resp(200, body)
  end
end
