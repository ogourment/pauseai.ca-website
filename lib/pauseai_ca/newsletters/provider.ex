defmodule PauseAiCa.Newsletters.Provider do
  @moduledoc "Read-only Brevo observations. Provider membership never grants local consent."
  alias PauseAiCa.{Newsletters, Repo, Volunteers}

  def refresh(scope, id) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %Newsletters.Subscription{} = subscription <- Repo.get(Newsletters.Subscription, uuid),
         {:ok, evidence} <- fetch(subscription.email) do
      Newsletters.observe_provider(scope, subscription.email, evidence)
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_found}
    end
  end

  defp fetch(email) do
    case Application.get_env(:pauseai_ca, :brevo_api_key) do
      key when is_binary(key) and key != "" ->
        request =
          Req.new(
            base_url:
              Application.get_env(:pauseai_ca, :brevo_base_url, "https://api.brevo.com/v3"),
            headers: [{"api-key", key}, {"accept", "application/json"}],
            receive_timeout: 8_000,
            retry: false
          )
          |> Req.merge(Application.get_env(:pauseai_ca, :brevo_req_options, []))

        case Req.get(request, url: "/contacts/" <> URI.encode_www_form(email)) do
          {:ok, %Req.Response{status: 200, body: %{"id" => id, "emailBlacklisted" => blocked}}}
          when is_integer(id) and is_boolean(blocked) ->
            {:ok,
             %{
               "provider_id" => id,
               "email_blacklisted" => blocked,
               "observed_at" => DateTime.to_iso8601(DateTime.utc_now())
             }}

          {:ok, %Req.Response{status: 404}} ->
            {:error, :not_found}

          _ ->
            {:error, :unavailable}
        end

      _ ->
        {:error, :not_configured}
    end
  end
end
