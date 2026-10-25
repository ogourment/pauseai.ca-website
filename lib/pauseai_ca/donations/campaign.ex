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

  defp value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp value(config, key) when is_map(config), do: Map.get(config, key)
  defp value(_, _), do: nil
end
