defmodule PauseAiCa.Campaigns.DeliveryTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias PauseAiCa.Campaigns
  alias PauseAiCa.Campaigns.Delivery
  alias PauseAiCa.Campaigns.Representative

  setup do
    member = %Representative{
      name: "Steven Guilbeault",
      district: "Laurier—Sainte-Marie",
      email: "Steven.Guilbeault@parl.gc.ca"
    }

    %{letter: Campaigns.compose_letter([member], :en, %{name: "Camille Roy"})}
  end

  describe "outside production" do
    test "the letter goes to the supporter, never to the MP", %{letter: letter} do
      assert {:ok, _result} =
               Delivery.deliver(letter, %{name: "Camille Roy", email: "camille@example.org"})

      assert_email_sent(fn email ->
        assert email.to == [{"", "camille@example.org"}]
        refute Enum.any?(email.to, fn {_name, address} -> address =~ "parl.gc.ca" end)
        assert email.subject =~ "[STAGING"
        assert email.subject =~ "Steven.Guilbeault@parl.gc.ca"
      end)
    end

    test "the body says plainly that nothing reached Parliament", %{letter: letter} do
      Delivery.deliver(letter, %{name: "Camille Roy", email: "camille@example.org"})

      assert_email_sent(fn email ->
        assert email.text_body =~ "NOT sent to a member of parliament"
      end)
    end
  end

  describe "in production" do
    setup do
      Application.put_env(:pauseai_ca, :campaign_rehearsal, false)
      on_exit(fn -> Application.put_env(:pauseai_ca, :campaign_rehearsal, true) end)
    end

    test "sends to the MP with the supporter as reply-to", %{letter: letter} do
      assert {:ok, _result} =
               Delivery.deliver(letter, %{name: "Camille Roy", email: "camille@example.org"})

      assert_email_sent(fn email ->
        assert email.reply_to == {"Camille Roy", "camille@example.org"}
        assert email.from == {"PauseAI Canada", "campaigns@example.org"}
        assert email.to == [{"", "Steven.Guilbeault@parl.gc.ca"}]
      end)
    end

    test "the numbered asks are emphasised in the HTML part", %{letter: letter} do
      Delivery.deliver(letter, %{name: "Camille Roy", email: "camille@example.org"})

      assert_email_sent(fn email ->
        assert email.html_body =~ "<strong>Raise this incident"
        assert email.text_body =~ "1. Raise this incident"
      end)
    end

    test "a letter cannot smuggle markup into the HTML part", %{letter: letter} do
      hostile = %{letter | body: "Hello <script>alert(1)</script>"}
      Delivery.deliver(hostile, %{name: "Camille", email: "camille@example.org"})

      assert_email_sent(fn email ->
        refute email.html_body =~ "<script>"
        assert email.html_body =~ "&lt;script&gt;"
      end)
    end
  end

  test "tells the MP's office the letter came through a campaign tool", %{letter: letter} do
    Delivery.deliver(letter, %{name: "Camille Roy", email: "camille@example.org"})

    assert_email_sent(fn email ->
      assert email.text_body =~ "Sent through pauseai.ca on behalf of Camille Roy"
      assert email.text_body =~ "camille@example.org"
    end)
  end

  test "refuses to send without a working reply address", %{letter: letter} do
    assert {:error, :invalid_email} = Delivery.deliver(letter, %{name: "Camille", email: "nope"})
    assert {:error, :invalid_email} = Delivery.deliver(letter, %{name: "Camille", email: nil})
    refute_email_sent()
  end

  test "refuses to send when no MP was resolved" do
    letter = Campaigns.compose_letter([], :en, %{name: "Camille Roy"})

    assert {:error, :no_recipient} =
             Delivery.deliver(letter, %{name: "Camille Roy", email: "camille@example.org"})

    refute_email_sent()
  end
end
