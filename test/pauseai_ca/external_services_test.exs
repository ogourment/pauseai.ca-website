defmodule PauseAiCa.ExternalServicesTest do
  use ExUnit.Case, async: false
  alias PauseAiCa.ExternalServices

  test "operation labels exclude recipient addresses, postal codes, credentials and arbitrary hosts" do
    for {url, classification} <- [
          {"https://api.brevo.com/v3/contacts/private%40example.com/campaignStats",
           {:brevo, :campaign_history}},
          {"https://api.brevo.com/v3/inbound/attachments/private-attachment",
           {:brevo, :download_attachment}},
          {"https://api.telegram.org/botprivate-token/sendMessage", {:telegram, :send_alert}},
          {"https://represent.opennorth.ca/postcodes/A1A1A1/", {:represent, :postcode_lookup}},
          {"https://personal.example.invalid/?secret=private", {:other_external, :unknown}}
        ] do
      assert ExternalServices.classify(Finch.build(:get, url)) == classification
    end
  end

  test "the configured receiver's private host gets distinct fixed operation names" do
    old = Application.fetch_env(:pauseai_ca, :agent_assistant)

    on_exit(fn ->
      case old do
        {:ok, config} -> Application.put_env(:pauseai_ca, :agent_assistant, config)
        :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
      end
    end)

    config = [
      anchor: [endpoint: "https://private.invalid/anchor/journal"],
      alert_delivery: [endpoint: "https://private.invalid/api/alerts"]
    ]

    Application.put_env(:pauseai_ca, :agent_assistant, config)

    assert ExternalServices.classify(Finch.build(:post, "https://private.invalid/anchor")) ==
             {:assistant_receiver, :anchor}

    assert ExternalServices.classify(
             Finch.build(:get, "https://private.invalid/api/alerts/secret-id/receipt")
           ) == {:assistant_receiver, :alert_delivery}

    assert ExternalServices.classify(
             Finch.build(:get, "https://private.invalid/api/alerts-other")
           ) == {:other_external, :unknown}
  end
end
