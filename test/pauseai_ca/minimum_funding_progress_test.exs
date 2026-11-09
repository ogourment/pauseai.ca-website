defmodule PauseAiCa.MinimumFundingProgressTest do
  use ExUnit.Case, async: false
  alias PauseAiCa.Donations.Campaign

  test "zero, partial, complete and overfunded pledges use the minimum with a capped bar" do
    for {pledged, tenths, bar, reached} <- [
          {0, 0, 0.0, false},
          {10_000, 10, 1.0, false},
          {989_999, 999, 99.9, false},
          {990_000, 1000, 100.0, true},
          {1_000_000, 1010, 100.0, true}
        ] do
      assert %{
               percent_tenths: ^tenths,
               bar_percent: ^bar,
               reached?: ^reached,
               minimum_minor: 990_000
             } = Campaign.minimum_progress(observation(pledged))
    end
  end

  test "missing, invalid and unrelated observations do not manufacture zero progress" do
    for value <- [
          nil,
          %{},
          observation(-1),
          Map.put(observation(10_000), :project_id, Ecto.UUID.generate()),
          Map.put(observation(10_000), :source_currency, "CAD"),
          Map.delete(observation(10_000), :pending_offer_minor)
        ] do
      assert Campaign.minimum_progress(value) == nil
    end
  end

  test "an invalid or absent campaign minimum hides progress safely" do
    original = Application.fetch_env!(:pauseai_ca, :manifund_campaign)
    on_exit(fn -> Application.put_env(:pauseai_ca, :manifund_campaign, original) end)

    for minimum <- [nil, 0, -1, "990000"] do
      Application.put_env(
        :pauseai_ca,
        :manifund_campaign,
        Keyword.put(original, :minimum_usd_minor, minimum)
      )

      assert Campaign.minimum_progress(observation(10_000)) == nil
    end
  end

  defp observation(pledged) do
    {:ok, campaign} = Campaign.current()

    %{
      project_id: campaign.project_id,
      measure: :pending_offers,
      source_currency: "USD",
      pending_offer_minor: pledged
    }
  end
end
