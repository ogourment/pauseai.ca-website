defmodule PauseAiCaWeb.HistoricalEmailController do
  use PauseAiCaWeb, :controller

  def show(conn, params) do
    with {:ok, %{messages: messages}} <-
           PauseAiCa.Outreach.get(conn.assigns.current_scope, params["conversation_id"]),
         message when not is_nil(message) <- Enum.find(messages, &(&1.id == params["message_id"])),
         "historical_import" <- message.source["kind"],
         {:ok, raw} <- Base.decode64(message.source["original_eml"] || "") do
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
      |> send_download({:binary, raw},
        filename: "original-email.eml",
        content_type: "application/octet-stream"
      )
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end
