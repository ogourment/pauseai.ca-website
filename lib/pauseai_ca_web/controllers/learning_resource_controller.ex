defmodule PauseAiCaWeb.LearningResourceController do
  use PauseAiCaWeb, :controller

  alias PauseAiCa.{Engagement, Library}

  def open(conn, %{"resource" => resource}) do
    case Library.resource(resource) do
      nil ->
        conn |> put_status(:not_found) |> text("Not found")

      entry ->
        user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

        Engagement.record_learning_signal(
          conn.assigns.learning_visitor_id,
          user,
          "resource_opened",
          resource
        )

        redirect(conn, external: entry.url)
    end
  end
end
