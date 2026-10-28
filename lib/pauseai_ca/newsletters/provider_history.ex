defmodule PauseAiCa.Newsletters.ProviderHistory do
  @moduledoc "Read-only bounded Brevo history requests, shared by polling and explicit results refresh."
  @page_size 500
  @max_pages 4
  def page_size, do: @page_size

  def pages(from, until, offset \\ 0, fetcher \\ &fetch_page/1) do
    pages(from, until, offset, fetcher, @max_pages, [])
  end

  defp pages(from, until, offset, fetcher, left, acc) do
    params = [
      startDate: Date.to_iso8601(from),
      endDate: Date.to_iso8601(until),
      offset: offset,
      limit: @page_size,
      sort: "asc"
    ]

    with {:ok, rows} when is_list(rows) and length(rows) <= @page_size <- fetcher.(params) do
      all = acc ++ rows

      cond do
        length(rows) < @page_size -> {:ok, %{events: all, offset: 0, partial: false}}
        left == 1 -> {:ok, %{events: all, offset: offset + @page_size, partial: true}}
        true -> pages(from, until, offset + @page_size, fetcher, left - 1, all)
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def fetch_page(params) do
    if PauseAiCa.MailSafety.environment() in [:production, :test],
      do: fetch_production_page(params),
      else: {:error, :environment_blocked}
  end

  defp fetch_production_page(params) do
    with key when is_binary(key) and key != "" <- Application.get_env(:pauseai_ca, :brevo_api_key) do
      request =
        Req.new(
          base_url: Application.get_env(:pauseai_ca, :brevo_base_url, "https://api.brevo.com/v3"),
          headers: [{"api-key", key}],
          receive_timeout: 8_000,
          connect_options: [timeout: 3_000],
          retry: false
        )
        |> Req.merge(Application.get_env(:pauseai_ca, :brevo_history_req_options, []))

      case Req.get(request, url: "/smtp/statistics/events", params: params) do
        {:ok, %{status: 200, body: %{"events" => rows}}} when is_list(rows) -> {:ok, rows}
        {:ok, %{status: 200}} -> {:error, :invalid_response}
        {:ok, %{status: 429}} -> {:error, :rate_limited}
        _ -> {:error, :unavailable}
      end
    else
      _ -> {:error, :not_configured}
    end
  rescue
    _ -> {:error, :unavailable}
  end
end
