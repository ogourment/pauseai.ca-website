defmodule PauseAiCa.AccountEmailHistory do
  @moduledoc "Read-only, recipient-scoped Brevo metadata. Never retrieves message bodies or links."
  alias PauseAiCa.AccountManagement
  @page_size 10
  @events_limit 100
  @campaign_events ~w(messagesSent delivered opened clicked hardBounces softBounces complaints)

  def defaults,
    do: %{
      "from" => Date.to_iso8601(Date.add(Date.utc_today(), -29)),
      "to" => Date.to_iso8601(Date.utc_today()),
      "page" => "1"
    }

  def load(scope, id, filters) do
    with {:ok, record} <- AccountManagement.get(scope, id),
         {:ok, range} <- range(filters),
         key when is_binary(key) and key != "" <- Application.get_env(:pauseai_ca, :brevo_api_key) do
      request =
        Req.new(
          base_url: Application.get_env(:pauseai_ca, :brevo_base_url, "https://api.brevo.com/v3"),
          headers: [{"api-key", key}],
          receive_timeout: 5_000,
          retry: false
        )
        |> Req.merge(
          Application.get_env(
            :pauseai_ca,
            :brevo_history_req_options,
            Application.get_env(:pauseai_ca, :brevo_req_options, [])
          )
        )

      result = %{
        account_id: id,
        transactional: transactions(request, record.user.email, range),
        campaigns: campaigns(request, record.user.email, range),
        filters: range
      }

      # Revocation during a provider request must not release its result to the caller.
      with {:ok, _} <- AccountManagement.get(scope, id), do: {:ok, result}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_configured}
    end
  end

  def range(filters) do
    with {:ok, from} <- Date.from_iso8601(filters["from"] || ""),
         {:ok, to} <- Date.from_iso8601(filters["to"] || ""),
         {page, ""} when page > 0 and page <= 1000 <- Integer.parse(filters["page"] || "1"),
         true <- Date.compare(to, Date.utc_today()) != :gt and Date.diff(to, from) in 0..89 do
      {:ok, %{from: Date.to_iso8601(from), to: Date.to_iso8601(to), page: page}}
    else
      _ -> {:error, :invalid_range}
    end
  end

  defp transactions(req, email, range) do
    case get(req, "/smtp/statistics/events",
           email: email,
           startDate: range.from,
           endDate: range.to,
           limit: @events_limit,
           offset: (range.page - 1) * @events_limit,
           sort: "desc"
         ) do
      {:ok, %{"events" => events}} when is_list(events) ->
        matching =
          Enum.filter(events, &(String.downcase(&1["email"] || "") == String.downcase(email)))

        groups = Enum.group_by(matching, & &1["messageId"])

        {allowed, excluded} =
          Enum.split_with(groups, fn {id, events} ->
            is_binary(id) and Enum.any?(events, &sender?(&1["from"]))
          end)

        rows =
          Enum.map(allowed, fn {id, events} ->
            %{
              id: "transaction:" <> id,
              subject: Enum.find_value(events, & &1["subject"]),
              sent_at:
                Enum.find_value(events, fn e -> if e["event"] == "requests", do: e["date"] end),
              events: Enum.map(events, &%{status: &1["event"], at: &1["date"]}) |> Enum.uniq(),
              kind: :transactional
            }
          end)

        success(rows, length(events) == @events_limit, excluded != [])

      {:ok, body} when body == %{} ->
        success([], false, false)

      {:ok, _} ->
        {:error, :invalid_response}

      error ->
        error
    end
  end

  defp campaigns(req, email, range) do
    case get(req, "/contacts/#{URI.encode(email, &URI.char_unreserved?/1)}/campaignStats",
           startDate: range.from,
           endDate: range.to
         ) do
      {:ok, body} when is_map(body) ->
        events =
          Enum.flat_map(@campaign_events, fn type ->
            Enum.flat_map(Map.get(body, type, []), fn row ->
              if type == "clicked" do
                Enum.map(
                  row["links"] || [],
                  &%{campaign: row["campaignId"], status: type, at: &1["eventTime"]}
                )
              else
                [%{campaign: row["campaignId"], status: type, at: row["eventTime"]}]
              end
            end)
          end)

        unsub = get_in(body, ["unsubscriptions", "userUnsubscription"]) || []

        events =
          events ++
            Enum.map(
              unsub,
              &%{campaign: &1["campaignId"], status: "unsubscribed", at: &1["eventTime"]}
            )

        groups =
          events
          |> Enum.reject(&is_nil(&1.campaign))
          |> Enum.group_by(& &1.campaign)
          |> Enum.sort_by(
            fn {_id, es} -> Enum.max(Enum.map(es, &(&1.at || "")), fn -> "" end) end,
            :desc
          )

        page = Enum.slice(groups, (range.page - 1) * @page_size, @page_size)

        results =
          Enum.map(page, fn {id, es} ->
            case get(req, "/emailCampaigns/#{id}", []) do
              {:ok, %{"sender" => %{"email" => sender}} = campaign} ->
                if sender?(sender) do
                  {:ok,
                   %{
                     id: "campaign:#{id}",
                     subject: campaign["subject"] || campaign["name"],
                     kind: :campaign,
                     sent_at:
                       Enum.find_value(es, fn e -> if e.status == "messagesSent", do: e.at end),
                     events: Enum.map(es, &Map.take(&1, [:status, :at])) |> Enum.uniq()
                   }}
                else
                  {:error, :sender_excluded}
                end

              _ ->
                {:error, :metadata_unavailable}
            end
          end)

        rows = for {:ok, row} <- results, do: row

        success(
          rows,
          length(groups) > range.page * @page_size,
          Enum.any?(results, &match?({:error, _}, &1))
        )

      {:error, :not_found} ->
        success([], false, false)

      {:ok, _} ->
        {:error, :invalid_response}

      error ->
        error
    end
  end

  defp success(rows, more, partial),
    do:
      {:ok, %{rows: rows, more: more, partial: partial, refreshed_at: DateTime.utc_now(:second)}}

  defp sender?(sender) when is_binary(sender) do
    domain = sender |> String.downcase() |> String.split("@") |> List.last()
    domain in Application.get_env(:pauseai_ca, :brevo_history_sender_domains, ["pauseai.ca"])
  end

  defp sender?(_), do: false

  defp get(req, path, params) do
    case Req.get(req, url: path, params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status}} when status in [401, 403] -> {:error, :unauthorized_provider}
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end
end
