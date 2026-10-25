defmodule PauseAiCaWeb.SlackOAuthController do
  use PauseAiCaWeb, :controller
  alias PauseAiCa.Chat.Slack

  def connect(conn, _) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    case Slack.begin_link(conn.assigns.current_scope, nonce) do
      {:ok, %{authorization_url: url}} ->
        conn |> put_session(:slack_link_nonce, nonce) |> redirect(external: url)

      _ ->
        conn
        |> put_flash(
          :error,
          gettext("Slack connection is unavailable. Please contact the site team.")
        )
        |> redirect(to: return_path(conn))
    end
  end

  def callback(conn, params) do
    result =
      Slack.complete_link(
        conn.assigns.current_scope,
        params["state"],
        get_session(conn, :slack_link_nonce),
        params["code"]
      )

    conn = delete_session(conn, :slack_link_nonce)

    case result do
      {:ok, _} ->
        conn
        |> put_flash(:info, gettext("Your Slack account is connected."))
        |> redirect(to: return_path(conn))

      _ ->
        conn
        |> put_flash(
          :error,
          gettext("Slack connection could not be verified. Start a new connection request.")
        )
        |> redirect(to: return_path(conn))
    end
  end

  defp return_path(conn),
    do: "/community/slack?" <> URI.encode_query(%{locale: conn.assigns[:locale] || "en"})
end
