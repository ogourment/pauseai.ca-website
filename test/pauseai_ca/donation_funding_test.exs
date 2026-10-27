defmodule PauseAiCa.DonationFundingTest do
  use ExUnit.Case, async: false
  alias PauseAiCa.Donations.Funding
  alias PhoenixDonations.Cache
  @now ~U[2026-10-27 12:00:00Z]
  @id "a7c581e9-fb40-e046-5996-1920a622fef7"

  test "public pending offers are converted with dated FX and never called received funds" do
    {:ok, observation} = Funding.fetch(fetcher(project(), fx()), @now)
    assert observation.pending_offer_minor == 10_001
    assert observation.amount_minor == 14_039
    assert observation.currency == "CAD"
    assert observation.measure == :pending_offers
    assert observation.received_minor == nil
    assert observation.fx_rate == "1.4038"
    assert observation.fx_date == ~D[2026-10-27]
    refute Map.has_key?(observation, :donors)
  end

  test "unsupported project lifecycle never produces a public funding amount" do
    for stage <- ["active", "completed", "cancelled", "unknown"] do
      assert {:error, :unavailable} =
               Funding.fetch(fetcher(Map.put(project(), "stage", stage), fx()), @now)
    end
  end

  test "missing, stale, future and malformed FX fail closed instead of assuming parity or zero" do
    for response <- [
          %{},
          fx("2026-10-19"),
          fx("2026-10-28"),
          fx("2026-10-27", "NaN"),
          fx("2026-10-27", "0"),
          fx("2026-10-27", "-1"),
          fx("2026-10-27", "Infinity")
        ] do
      assert {:error, :unavailable} = Funding.fetch(fetcher(project(), response), @now)
    end
  end

  test "cache reads never fetch and a last good observation expires despite later cache reads" do
    {:ok, value} = Funding.fetch(fetcher(project(), fx()), @now)
    parent = self()

    cache =
      start_supervised!(
        {Cache,
         fetcher: fn ->
           send(parent, :provider_fetch)
           {:ok, value}
         end,
         refresh_interval_ms: :infinity,
         clock: fn -> @now end,
         max_age_seconds: 900}
      )

    assert_receive :provider_fetch
    assert {:ok, observation} = await_observation(cache, 30)
    assert observation.amount_minor == 14_039
    assert {:ok, _} = Funding.observation(cache, @now)
    assert {:error, :unavailable} = Funding.observation(cache, DateTime.add(@now, 901))
    refute_receive :provider_fetch
  end

  test "missing cache and disabled provider return a safe unavailable result" do
    assert {:error, :unavailable} = Funding.observation(:nonexistent_donation_cache, @now)
    assert {:error, :unavailable} = Funding.observation()
  end

  defp await_observation(cache, left) do
    case Funding.observation(cache, @now) do
      {:ok, _} = result ->
        result

      _ when left > 0 ->
        Process.sleep(10)
        await_observation(cache, left - 1)

      other ->
        other
    end
  end

  defp fetcher(project, fx),
    do: fn url ->
      if String.starts_with?(url, "https://manifund.org/"), do: {:ok, [project]}, else: {:ok, fx}
    end

  defp project,
    do: %{
      "id" => @id,
      "type" => "grant",
      "stage" => "proposal",
      "bids" => [
        %{"status" => "pending", "amount" => 100.01},
        %{"status" => "cancelled", "amount" => 999},
        %{"status" => "accepted", "amount" => 500}
      ],
      "txns" => [%{"amount" => 1_000_000}]
    }

  defp fx(date \\ "2026-10-27", rate \\ "1.4038"),
    do: %{"observations" => [%{"d" => date, "FXUSDCAD" => %{"v" => rate}}]}
end
