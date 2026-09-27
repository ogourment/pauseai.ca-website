defmodule PauseAiCaWeb.Site do
  @moduledoc "Locale and trusted public origins for the bilingual site."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      case conn.path_info do
        [locale | _] when locale in ["en", "fr"] ->
          locale

        _ ->
          valid_locale(conn.params["locale"]) || get_session(conn, :site_locale) ||
            default_locale(conn.host)
      end

    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    conn |> assign(:locale, locale) |> put_session(:site_locale, locale)
  end

  def on_mount(:default, params, session, socket) do
    locale = valid_locale(params["locale"]) || session["site_locale"] || "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  def locale(params, socket),
    do: valid_locale(params["locale"]) || socket.assigns[:locale] || "en"

  def default_locale(host) do
    french = Application.get_env(:pauseai_ca, :public_origins, %{})["fr"]
    if french && URI.parse(french).host == host, do: "fr", else: "en"
  end

  def url(locale, path) do
    origin =
      Application.get_env(:pauseai_ca, :public_origins, %{})[locale] ||
        PauseAiCaWeb.Endpoint.url()

    # Origins come from deployment configuration, never from a submitted Host or URL.
    origin <> path
  end

  defp valid_locale(locale) when locale in ["en", "fr"], do: locale
  defp valid_locale(_), do: nil
end
