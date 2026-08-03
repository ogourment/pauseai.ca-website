defmodule PauseAiCaWeb.Plugs.RequireInvited do
  @moduledoc """
  Closes the whole site to anyone who is not signed in.

  Staging runs on a real domain with a real certificate, and the campaign page
  can send email to a member of parliament. Left open, that is an unauthenticated
  relay pointed at Parliament, signed by our own domain. This plug makes the
  environment reachable only by people who have proved they control an email
  address.

  Enabled with `config :pauseai_ca, :require_invited, true`. Production leaves it
  off; the public site is meant to be public, and the send path is protected
  there by confirming the supporter's address instead.

  Authentication routes stay open, or nobody could ever get in.
  """

  use PauseAiCaWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  @always_open [
    ~r{^/users/log-in},
    ~r{^/users/log-out},
    ~r{^/users/register},
    ~r{^/health},
    ~r{^/images/},
    ~r{^/fonts/},
    ~r{^/assets/},
    ~r{^/favicon},
    ~r{^/robots\.txt$}
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      not enabled?() -> conn
      conn.assigns[:current_scope] -> conn
      open_path?(conn.request_path) -> conn
      true -> redirect_to_login(conn)
    end
  end

  defp enabled?, do: Application.get_env(:pauseai_ca, :require_invited, false)

  defp open_path?(path), do: Enum.any?(@always_open, &Regex.match?(&1, path))

  defp redirect_to_login(conn) do
    conn
    |> put_flash(:error, message(conn))
    |> maybe_store_return_to()
    |> redirect(to: ~p"/users/log-in")
    |> halt()
  end

  # Mirrors UserAuth's return-to handling so a visitor lands where they meant to.
  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp message(conn) do
    if String.starts_with?(conn.request_path, "/fr") do
      "Ce site est en préversion. Connectez-vous pour y accéder."
    else
      "This site is in preview. Sign in to continue."
    end
  end
end
