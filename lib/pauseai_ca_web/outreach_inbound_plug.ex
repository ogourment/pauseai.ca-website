defmodule PauseAiCaWeb.OutreachInboundPlug do
  @moduledoc "Authenticated, bounded durable receipt before JSON parameter logging."
  import Plug.Conn
  @path "/webhooks/brevo/inbound"
  @limit 2_097_152

  def init(opts), do: opts

  def call(%{request_path: @path} = conn, _opts) do
    cond do
      conn.method != "POST" ->
        respond(conn, 405, "method_not_allowed")

      not Application.get_env(:pauseai_ca, :outreach_inbound_enabled, false) ->
        respond(conn, 503, "not_activated")

      not authenticated?(conn) ->
        respond(conn, 401, "unauthorized")

      true ->
        receive_payload(conn)
    end
  end

  def call(conn, _opts), do: conn

  defp authenticated?(conn) do
    expected = Application.get_env(:pauseai_ca, :outreach_webhook_token)

    with true <- is_binary(expected) and byte_size(expected) in 32..512,
         [header] <- get_req_header(conn, "authorization"),
         [_, token] <- Regex.run(~r/\ABearer ([^\s]+)\z/i, header),
         true <- byte_size(token) == byte_size(expected) do
      Plug.Crypto.secure_compare(token, expected)
    else
      _ -> false
    end
  end

  defp receive_payload(conn) do
    case read_body(conn, length: @limit, read_length: 65_536, read_timeout: 10_000) do
      {:ok, body, conn} when byte_size(body) <= @limit ->
        with {:ok, %{"items" => items} = payload} <- Jason.decode(body),
             true <- is_list(items) and length(items) in 1..100,
             {:ok, receipt} <- PauseAiCa.Outreach.receive(payload) do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(202, Jason.encode!(%{receipt_id: receipt.id}))
          |> halt()
        else
          {:error, %Jason.DecodeError{}} -> respond(conn, 400, "invalid_json")
          {:error, _} -> respond(conn, 503, "receipt_unavailable")
          _ -> respond(conn, 400, "invalid_payload")
        end

      {:ok, _, conn} ->
        respond(conn, 413, "payload_too_large")

      {:more, _, conn} ->
        respond(conn, 413, "payload_too_large")

      {:error, _} ->
        respond(conn, 400, "invalid_body")
    end
  end

  defp respond(conn, status, error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: error}))
    |> halt()
  end
end
