defmodule PauseAiCaWeb.NewsletterRecipientExportController do
  use PauseAiCaWeb, :controller

  def show(conn, %{"id" => id}) do
    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")

    case PauseAiCa.Newsletters.RecipientExport.download(conn.assigns.current_scope, id) do
      {:ok, export} ->
        send_download(conn, {:binary, export.content},
          filename: export.filename,
          content_type: "text/csv; charset=utf-8"
        )

      {:error, :unauthorized} ->
        send_resp(conn, :not_found, "Not found")
    end
  end
end
