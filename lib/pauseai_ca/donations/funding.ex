defmodule PauseAiCa.Donations.Funding do
  @moduledoc "Read-only cached pending offers, with dated CAD conversion; never a received-funds total."
  alias PhoenixDonations.{Cache, Providers.Manifund}
  @server __MODULE__.Cache
  @fx_url "https://www.bankofcanada.ca/valet/observations/FXUSDCAD/json?recent=1"
  @max_age 900
  @fx_max_days 7

  def children do
    if enabled?() do
      [
        {Cache,
         name: @server,
         fetcher: &fetch/0,
         refresh_interval_ms: 300_000,
         fetch_timeout_ms: 20_000,
         max_age_seconds: @max_age}
      ]
    else
      []
    end
  end

  @doc "Cache-only public read. Unsupported, stale, disabled or unavailable observations fail closed."
  def observation do
    if enabled?() do
      observation(
        Application.get_env(:pauseai_ca, :donation_funding_cache, @server),
        DateTime.utc_now()
      )
    else
      {:error, :unavailable}
    end
  end

  def observation(server, now) do
    case Cache.get(server) do
      {:ok, %{status: :fresh, value: value, last_success_at: checked_at}} ->
        case validate_observation(value, now) do
          :ok ->
            {:ok,
             value |> Map.put(:checked_at, checked_at) |> Map.put(:last_success_at, checked_at)}

          _ ->
            {:error, :unavailable}
        end

      _ ->
        {:error, :unavailable}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  def fetch do
    fetch(&PauseAiCa.Donations.FundingHTTP.get_json/1, DateTime.utc_now())
  end

  @doc false
  def fetch(get_json, now) do
    with {:ok, campaign} <- PauseAiCa.Donations.Campaign.current(),
         {:ok, pending} <- Manifund.fetch(campaign.project_id, get_json, max_pages: 10),
         {:ok, fx_json} <- get_json.(@fx_url),
         {:ok, rate, date} <- fx(fx_json, now) do
      amount = pending.pending_offer_minor |> Decimal.new() |> Decimal.mult(rate)
      amount_minor = amount |> Decimal.round(0, :half_up) |> Decimal.to_integer()

      if amount_minor <= 9_007_199_254_740_991 do
        {:ok,
         %{
           project_id: campaign.project_id,
           amount_minor: amount_minor,
           currency: "CAD",
           measure: :pending_offers,
           pending_offer_minor: pending.pending_offer_minor,
           source_currency: "USD",
           received_minor: nil,
           source: pending.source,
           limitation: pending.limitation,
           fx_rate: Decimal.to_string(rate, :normal),
           fx_date: date,
           fx_source: @fx_url,
           fetched_at: now
         }}
      else
        {:error, :unavailable}
      end
    else
      _ -> {:error, :unavailable}
    end
  end

  defp fx(%{"observations" => [%{"d" => date, "FXUSDCAD" => %{"v" => value}}]}, now)
       when is_binary(value) and is_binary(date) do
    with true <- String.match?(value, ~r/\A[0-9]{1,2}(?:\.[0-9]{1,8})?\z/),
         {:ok, date} <- Date.from_iso8601(date),
         true <- recent_date?(date, now),
         {rate, ""} <- Decimal.parse(value),
         true <- Decimal.compare(rate, Decimal.new(0)) == :gt,
         true <- Decimal.compare(rate, Decimal.new(10)) == :lt do
      {:ok, rate, date}
    else
      _ -> {:error, :invalid_fx}
    end
  end

  defp fx(_, _), do: {:error, :invalid_fx}

  defp validate_observation(
         %{
           amount_minor: amount,
           currency: "CAD",
           measure: :pending_offers,
           received_minor: nil,
           fx_date: %Date{} = date,
           fetched_at: %DateTime{} = observed
         },
         now
       )
       when is_integer(amount) and amount >= 0 do
    age = DateTime.diff(now, observed)
    if age >= 0 and age <= @max_age and recent_date?(date, now), do: :ok, else: :error
  end

  defp validate_observation(_, _), do: :error

  defp enabled? do
    Application.get_env(:pauseai_ca, :donation_funding_enabled, false) and
      Application.get_env(:pauseai_ca, :manifund_donations_enabled, false)
  end

  defp recent_date?(date, %DateTime{} = now) do
    age = Date.diff(DateTime.to_date(now), date)
    age >= 0 and age <= @fx_max_days
  end
end
