defmodule PauseAiCaWeb.OutreachAttachmentController do
  use PauseAiCaWeb, :controller

  def show(conn, params) do
    with {item, ""} <- Integer.parse(params["item_index"]),
         {attachment, ""} <- Integer.parse(params["attachment_index"]),
         {:ok, file} <-
           PauseAiCa.OutreachAttachments.download(
             conn.assigns.current_scope,
             params["receipt_id"],
             item,
             attachment
           ) do
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
      |> send_download({:file, file.path},
        filename: file.filename,
        content_type: "application/octet-stream"
      )
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end
