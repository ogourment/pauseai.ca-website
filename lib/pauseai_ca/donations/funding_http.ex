defmodule PauseAiCa.Donations.FundingHTTP do
  @moduledoc false
  @doc "Public unauthenticated JSON reads only; failures never include provider bodies or identities."
  def get_json(url) do
    case Req.get(url,
           connect_options: [timeout: 3_000],
           receive_timeout: 5_000,
           retry: false,
           redirect: false,
           headers: [{"accept", "application/json"}]
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) or is_list(body) -> {:ok, body}
      _ -> {:error, :provider_unavailable}
    end
  end

  @doc "Read-only project-details RPC; never log or persist the response body."
  def post_rpc("https://manifund.org/api/mcp" = url, request) do
    case Req.post(url,
           json: request,
           connect_options: [timeout: 3_000],
           receive_timeout: 5_000,
           retry: false,
           redirect: false,
           headers: [
             {"accept", "application/json, text/event-stream"},
             {"mcp-protocol-version", "2025-03-26"}
           ]
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        body
        |> String.split("\n")
        |> Enum.find_value({:error, :provider_unavailable}, fn
          "data: " <> json ->
            case JSON.decode(json) do
              {:ok, %{"id" => 1} = reply} -> {:ok, reply}
              _ -> nil
            end

          _ ->
            nil
        end)

      _ ->
        {:error, :provider_unavailable}
    end
  end
end
