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
end
