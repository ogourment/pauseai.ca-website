defmodule PauseAiCa.ExternalLinksTest do
  @moduledoc """
  Checks that every external link we publish still resolves.

  This test reaches the public internet, so it is tagged `:external` and
  excluded from the default run. Run it before publishing an editorial change:

      mix test --only external

  Two of these links were already dead when this test was written, which is why
  it exists.
  """

  use ExUnit.Case, async: true

  alias PauseAiCa.Campaigns
  alias PauseAiCa.Library

  @moduletag :external
  @moduletag timeout: 120_000

  test "every published external link resolves" do
    urls =
      (library_urls() ++ voice_urls() ++ campaign_urls())
      |> Enum.uniq()

    broken =
      urls
      |> Task.async_stream(&{&1, status(&1)}, max_concurrency: 6, timeout: :infinity)
      |> Enum.flat_map(fn {:ok, {url, status}} ->
        if status in 200..399, do: [], else: [{url, status}]
      end)

    assert broken == [], "dead links: #{inspect(broken, pretty: true)}"
  end

  defp library_urls, do: Enum.map(Library.resources(), & &1.url)

  defp voice_urls do
    Enum.flat_map(Library.voices(), fn voice ->
      Enum.map(voice.quotes, & &1.url) ++ Enum.map(voice.references, & &1.url)
    end)
  end

  defp campaign_urls do
    campaign = Campaigns.current_warning_shot()
    Enum.map(campaign.updates, & &1.url) ++ Map.values(campaign.links)
  end

  defp status(url) do
    case Req.get(url, redirect: true, receive_timeout: 20_000, retry: false) do
      {:ok, %Req.Response{status: status}} -> status
      {:error, reason} -> inspect(reason)
    end
  end
end
