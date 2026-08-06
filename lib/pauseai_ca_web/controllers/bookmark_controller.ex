defmodule PauseAiCaWeb.BookmarkController do
  use PauseAiCaWeb, :controller

  alias PauseAiCa.Accounts

  def create(conn, %{"resource" => resource} = params) do
    locale = if params["locale"] == "fr", do: "fr", else: "en"

    case Accounts.save_resource(conn.assigns.current_scope.user, resource) do
      {:ok, _user} ->
        conn
        |> put_flash(
          :info,
          gettext("Resource saved.")
        )
        |> redirect(to: "/#{locale}#resource-#{resource}")

      {:error, :unknown_resource} ->
        conn
        |> put_flash(
          :error,
          gettext("Unknown resource.")
        )
        |> redirect(to: "/#{locale}")
    end
  end
end
