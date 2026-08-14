defmodule PauseAiCaWeb.BookmarkController do
  use PauseAiCaWeb, :controller

  alias PauseAiCa.{Accounts, Engagement, Library}

  def create(conn, %{"resource" => resource} = params) do
    locale = if params["locale"] == "fr", do: "fr", else: "en"

    case Accounts.save_resource(conn.assigns.current_scope.user, resource) do
      {:ok, _user} ->
        Engagement.record_learning_signal(
          conn.assigns.learning_visitor_id,
          conn.assigns.current_scope.user,
          "resource_bookmarked",
          resource
        )

        conn
        |> put_flash(
          :info,
          gettext("Resource saved.")
        )
        |> redirect(to: saved_resource_path(resource, locale))

      {:error, :unknown_resource} ->
        conn
        |> put_flash(
          :error,
          gettext("Unknown resource.")
        )
        |> redirect(to: "/#{locale}")
    end
  end

  defp saved_resource_path(resource, "fr") do
    if Library.resource(resource),
      do: "/fr/comprendre#resource-#{resource}",
      else: "/fr#resource-#{resource}"
  end

  defp saved_resource_path(resource, _locale) do
    if Library.resource(resource),
      do: "/en/learn#resource-#{resource}",
      else: "/en#resource-#{resource}"
  end
end
