defmodule PauseAiCa.BrevoHistoryStub do
  @moduledoc "Synthetic Brevo responses; records read-only requests and never sends mail."
  import Plug.Conn

  def call(conn, _) do
    conn = fetch_query_params(conn)

    if pid = Application.get_env(:pauseai_ca, :history_test_process),
      do: send(pid, {:history_request, conn.method, conn.request_path})

    now = DateTime.utc_now(:second) |> DateTime.to_iso8601()

    case {conn.method, String.replace_prefix(conn.request_path, "/v3", "")} do
      {"GET", "/smtp/statistics/events"} ->
        event = %{
          "email" => conn.query_params["email"],
          "messageId" => "synthetic-message",
          "from" => "hello@pauseai.ca",
          "subject" => "Your sign-in link",
          "date" => now
        }

        json(conn, 200, %{
          "events" => [
            Map.put(event, "event", "requests"),
            Map.put(event, "event", "delivered"),
            Map.merge(event, %{
              "event" => "clicks",
              "link" => "https://secret.example/sign-in-secret",
              "ip" => "192.0.2.1"
            }),
            Map.merge(event, %{
              "messageId" => "other-org",
              "from" => "hello@other.example",
              "subject" => "Other organization"
            })
          ]
        })

      {"GET", "/emailCampaigns/41"} ->
        json(conn, 200, %{
          "subject" => "September update",
          "sender" => %{"email" => "news@pauseai.ca"}
        })

      {"GET", path} ->
        if String.ends_with?(path, "/campaignStats") do
          if Application.get_env(:pauseai_ca, :history_test_failure, false),
            do: json(conn, 429, %{}),
            else:
              json(conn, 200, %{
                "messagesSent" => [%{"campaignId" => 41, "eventTime" => now}],
                "delivered" => [%{"campaignId" => 41, "eventTime" => now}],
                "opened" => [%{"campaignId" => 41, "eventTime" => now, "ip" => "192.0.2.1"}],
                "clicked" => [
                  %{
                    "campaignId" => 41,
                    "links" => [
                      %{"eventTime" => now, "url" => "https://secret.example/campaign-secret"}
                    ]
                  }
                ]
              })
        else
          json(conn, 404, %{})
        end

      _ ->
        raise "History must never write to Brevo"
    end
  end

  defp json(conn, code, value),
    do: conn |> put_resp_content_type("application/json") |> send_resp(code, Jason.encode!(value))
end
