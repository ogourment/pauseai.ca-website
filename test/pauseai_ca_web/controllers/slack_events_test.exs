defmodule PauseAiCaWeb.SlackEventsTest do
  use PauseAiCaWeb.ConnCase, async: false
  alias PauseAiCa.{SlackFixtures, Repo}
  alias PauseAiCa.Chat.{Slack, SlackInbox, SlackMessage}

  setup do
    saved = SlackFixtures.configure!()
    on_exit(fn -> SlackFixtures.restore!(saved) end)
    :ok
  end

  defp signed(conn, raw, signature \\ nil) do
    ts = Integer.to_string(System.system_time(:second))

    signature =
      signature ||
        "v0=" <>
          Base.encode16(:crypto.mac(:hmac, :sha256, "synthetic-signing", "v0:#{ts}:#{raw}"),
            case: :lower
          )

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-slack-request-timestamp", ts)
    |> put_req_header("x-slack-signature", signature)
    |> post("/integrations/slack/events", raw)
  end

  test "actual endpoint commits signed bytes once before acknowledging and projects later", %{
    conn: conn
  } do
    raw =
      Jason.encode!(%{
        "type" => "event_callback",
        "team_id" => "T1",
        "api_app_id" => "A1",
        "event_id" => "EvEndpoint",
        "event" => %{
          "type" => "message",
          "channel" => "C1",
          "user" => "U1",
          "ts" => "1800000000.000001",
          "text" => "Synthetic endpoint message"
        }
      })

    assert signed(conn, raw).status == 200
    assert Repo.one!(SlackInbox).status == "pending"
    assert Repo.aggregate(SlackMessage, :count) == 0
    assert signed(build_conn(), raw).status == 200
    assert Repo.aggregate(SlackInbox, :count) == 1
    assert :ok = Slack.process_pending()
    assert Repo.one!(SlackInbox).status == "processed"
    assert Repo.one!(SlackMessage).text == "Synthetic endpoint message"
    assert signed(build_conn(), raw <> " ", "v0=" <> String.duplicate("0", 64)).status == 403
    assert Repo.aggregate(SlackInbox, :count) == 1
  end

  test "signed challenge is separate from event/durability proof", %{conn: conn} do
    raw = Jason.encode!(%{"type" => "url_verification", "challenge" => "synthetic-challenge"})
    response = signed(conn, raw)
    assert json_response(response, 200) == %{"challenge" => "synthetic-challenge"}
    assert Repo.aggregate(SlackInbox, :count) == 0
    Application.put_env(:pauseai_ca, :slack_enabled, false)
    assert signed(build_conn(), raw).status == 503
  end
end
