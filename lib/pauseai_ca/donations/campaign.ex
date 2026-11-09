defmodule PauseAiCa.Donations.Campaign do
  @moduledoc "Consumer-configured public campaign handoff; rendering never calls the provider."

  def current do
    config = Application.get_env(:pauseai_ca, :manifund_campaign, [])
    id = value(config, :project_id)
    url = value(config, :url)

    with {:ok, _} <- Ecto.UUID.cast(id),
         true <- is_binary(url),
         %URI{
           scheme: "https",
           host: "manifund.org",
           path: "/projects/" <> slug,
           userinfo: nil,
           query: nil,
           fragment: nil,
           port: 443
         } <- URI.parse(url),
         true <- slug != "" and String.match?(slug, ~r/\A[a-z0-9-]+\z/) do
      {:ok, %{project_id: id, url: url}}
    else
      _ -> {:error, :not_configured}
    end
  end

  @doc "Progress from observed USD pledges toward this campaign’s configured USD minimum."
  def minimum_progress(%{
        project_id: project_id,
        measure: :pending_offers,
        source_currency: "USD",
        pending_offer_minor: pledged
      })
      when is_integer(pledged) and pledged >= 0 do
    config = Application.get_env(:pauseai_ca, :manifund_campaign, [])

    with {:ok, %{project_id: ^project_id}} <- current(),
         minimum when is_integer(minimum) and minimum > 0 <- value(config, :minimum_usd_minor) do
      # Round down so a pledge just below the minimum never displays 100%.
      percent_tenths = div(pledged * 1000, minimum)

      %{
        pledged_minor: pledged,
        minimum_minor: minimum,
        percent_tenths: percent_tenths,
        bar_percent: min(percent_tenths, 1000) / 10,
        reached?: pledged >= minimum
      }
    else
      _ -> nil
    end
  end

  def minimum_progress(_), do: nil

  @doc "Fallback settings for pre-existing CMS snapshots; no public read persists defaults."
  def defaults do
    config = Application.get_env(:pauseai_ca, :manifund_campaign, [])

    %{
      "enabled" => true,
      "closes_at" => value(config, :closes_at) || "",
      "urgent_window_days" => value(config, :urgent_window_days) || 7
    }
  end

  def settings(page) do
    overrides = if is_map(page), do: page["campaign"], else: nil

    case overrides do
      nil -> defaults()
      value when is_map(value) -> Map.merge(defaults(), value)
      _ -> Map.put(defaults(), "enabled", false)
    end
  end

  @doc "Server-clock campaign state. Invalid, disabled or expired campaigns never promote urgency."
  def countdown(page \\ nil, now \\ DateTime.utc_now()) do
    settings = settings(page)

    with true <- Application.get_env(:pauseai_ca, :manifund_donations_enabled, false),
         true <- settings["enabled"] == true,
         deadline when is_binary(deadline) <- settings["closes_at"],
         {:ok, closes_at, _} <- DateTime.from_iso8601(deadline),
         days when is_integer(days) and days in 0..90 <- settings["urgent_window_days"],
         seconds when seconds > 0 <- DateTime.diff(closes_at, now) do
      %{
        closes_at: closes_at,
        closing_date: String.slice(settings["closes_at"], 0, 10),
        now: now,
        seconds: seconds,
        urgent_at: DateTime.add(closes_at, -days * 86_400),
        urgent?: seconds <= days * 86_400,
        parts: %{
          days: div(seconds, 86_400),
          hours: rem(div(seconds, 3600), 24),
          minutes: rem(div(seconds, 60), 60),
          seconds: rem(seconds, 60)
        }
      }
    else
      _ -> nil
    end
  end

  defp value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp value(config, key) when is_map(config), do: Map.get(config, key)
  defp value(_, _), do: nil
end
