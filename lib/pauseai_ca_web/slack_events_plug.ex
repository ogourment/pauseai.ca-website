defmodule PauseAiCaWeb.SlackEventsPlug do
  @moduledoc false
  import Plug.Conn
  alias PauseAiCa.Chat.Slack
  alias PhoenixCommunity.Slack.Signature
  def init(opts), do: opts

  def call(%{method: "POST", request_path: "/integrations/slack/events"} = conn, _) do
    if Slack.configured?() do
      case read_body(conn, length: 1_048_576, read_length: 1_048_576, read_timeout: 5_000) do
        {:ok, raw, conn} -> receive_signed(conn, raw)
        {:more, _, conn} -> finish(conn, 413, %{"error" => "request_too_large"})
        {:error, _} -> finish(conn, 400, %{"error" => "invalid_body"})
      end
    else
      finish(conn, 503, %{"error" => "not_configured"})
    end
  end

  def call(conn, _), do: conn

  defp receive_signed(conn, raw) do
    with [timestamp] <- get_req_header(conn, "x-slack-request-timestamp"),
         [signature] <- get_req_header(conn, "x-slack-signature"),
         :ok <-
           Signature.verify(
             raw,
             timestamp,
             signature,
             Application.get_env(:pauseai_ca, :slack, %{})[:signing_secret]
           ),
         {:ok, body} <- Jason.decode(raw) do
      case body do
        %{"type" => "url_verification", "challenge" => challenge}
        when is_binary(challenge) and byte_size(challenge) <= 256 ->
          finish(conn, 200, %{"challenge" => challenge})

        _ ->
          case Slack.ingest(raw, timestamp, signature) do
            {:ok, _} ->
              finish(conn, 200, %{"accepted" => true})

            {:error, reason} when reason in [:persistence_failed, :intake_failed] ->
              finish(conn, 503, %{"error" => "retry_later"})

            _ ->
              finish(conn, 403, %{"error" => "rejected"})
          end
      end
    else
      _ -> finish(conn, 403, %{"error" => "invalid_signature"})
    end
  end

  defp finish(conn, status, body),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(body))
      |> halt()
end
