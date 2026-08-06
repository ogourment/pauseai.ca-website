defmodule PauseAiCa.Campaigns.SubscriptionTest do
  use ExUnit.Case, async: true

  alias PauseAiCa.Campaigns.Subscription

  test "subscribes a new address" do
    assert {:ok, :subscribed} = Subscription.subscribe("camille@example.org", "fr")
  end

  test "sends optional city and postal code as Brevo attributes" do
    assert {:ok, :subscribed} =
             Subscription.subscribe("located@example.org", "fr", %{
               "postal_code" => "H2X 1Y4",
               "city" => "Montréal"
             })
  end

  test "reads optional location from an existing contact" do
    assert {:ok, %{postal_code: "H2X 1Y4", city: "Montréal"}} =
             Subscription.location_for("location@example.org")
  end

  test "treats an address Brevo already knows as success" do
    assert {:ok, :already_subscribed} = Subscription.subscribe("taken@example.org", "en")
  end

  test "rejects an address that cannot receive mail" do
    assert {:error, :invalid_email} = Subscription.subscribe("nope", "en")
    assert {:error, :invalid_email} = Subscription.subscribe("", "en")
  end

  test "reports when Brevo is unreachable" do
    assert {:error, :unavailable} = Subscription.subscribe("broken@example.org", "en")
  end

  test "says so rather than failing silently when no key is configured" do
    original = Application.get_env(:pauseai_ca, :brevo_api_key)
    Application.put_env(:pauseai_ca, :brevo_api_key, nil)
    on_exit(fn -> Application.put_env(:pauseai_ca, :brevo_api_key, original) end)

    assert {:error, :not_configured} = Subscription.subscribe("camille@example.org", "en")
  end
end
