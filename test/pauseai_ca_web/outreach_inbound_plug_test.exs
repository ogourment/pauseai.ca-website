defmodule PauseAiCaWeb.OutreachInboundPlugTest do
  use PauseAiCaWeb.ConnCase, async: false
  alias PauseAiCa.Repo
  alias PauseAiCa.Outreach.Receipt
  alias PauseAiCaWeb.OutreachInboundPlug

  setup do
    previous =
      for key <- [:outreach_inbound_enabled, :outreach_webhook_token],
          into: %{},
          do: {key, Application.get_env(:pauseai_ca, key)}

    token = String.duplicate("SyntheticWebhookOnly", 3)
    Application.put_env(:pauseai_ca, :outreach_inbound_enabled, true)
    Application.put_env(:pauseai_ca, :outreach_webhook_token, token)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> Application.put_env(:pauseai_ca, key, value) end)
    end)

    %{token: token}
  end

  test "authenticated callbacks are durable before acknowledgement and exact retry is one receipt",
       %{token: token} do
    payload = Jason.encode!(%{"items" => [%{"MessageId" => "<synthetic@example.org>"}]})
    first = callback(payload, token)
    assert first.status == 202
    id = Jason.decode!(first.resp_body)["receipt_id"]
    assert Repo.get!(Receipt, id).state == "pending"
    again = callback(payload, token)
    assert Jason.decode!(again.resp_body)["receipt_id"] == id
    assert Repo.aggregate(Receipt, :count) == 1
    refute_received {:email, _}
  end

  test "unauthenticated and disabled callbacks cannot create receipts", %{token: token} do
    assert callback(~s({"items":[{}]}), "wrong").status == 401
    Application.put_env(:pauseai_ca, :outreach_inbound_enabled, false)
    assert callback(~s({"items":[{}]}), token).status == 503
    assert Repo.aggregate(Receipt, :count) == 0
  end

  test "malformed and oversized bodies are rejected without acknowledging a receipt", %{
    token: token
  } do
    assert callback("{", token).status == 400
    assert callback(~s({"items":[]}), token).status == 400

    oversized =
      Jason.encode!(%{"items" => [%{"RawTextBody" => String.duplicate("x", 2_097_152)}]})

    assert callback(oversized, token).status == 413
    assert Repo.aggregate(Receipt, :count) == 0
  end

  defp callback(body, token) do
    :post
    |> Plug.Test.conn("/webhooks/brevo/inbound", body)
    |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)
    |> OutreachInboundPlug.call([])
  end
end
