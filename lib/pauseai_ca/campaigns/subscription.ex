defmodule PauseAiCa.Campaigns.Subscription do
  @moduledoc """
  Subscribes a supporter to the PauseAI Canada mailing list in Brevo.

  Brevo, not our database, is the record for people who ask for updates. That
  keeps one copy of an email address under one set of unsubscribe and retention
  controls rather than two.

  We send the address, the language they read the site in, the country, and any
  city or postal code they chose to provide. We do not send anything they did
  not type, and the caller must have taken an
  explicit opt-in — see `PauseAiCaWeb.SubscribeLive` for the consent wording.
  """

  @brevo_base_url "https://api.brevo.com/v3"

  @doc """
  Adds `email` to the configured Brevo list.

  Returns `{:error, :not_configured}` when no API key is set, which is the
  normal state in development, and `{:ok, :already_subscribed}` when Brevo
  already knows the address so the caller can show the same friendly message
  either way.
  """
  @spec subscribe(String.t(), String.t(), map()) ::
          {:ok, :subscribed | :already_subscribed}
          | {:error, :invalid_email | :not_configured | :unavailable}
  def subscribe(email, locale, location \\ %{}) do
    with {:ok, address} <- validate_email(email),
         {:ok, api_key} <- api_key() do
      request(address, locale, location, api_key)
    end
  end

  @doc "Returns optional location attributes for an existing Brevo contact."
  @spec location_for(String.t()) :: {:ok, map()} | {:error, :not_found | :unavailable}
  def location_for(email) do
    with {:ok, address} <- validate_email(email),
         {:ok, api_key} <- api_key() do
      case Req.get(req(api_key), url: "/contacts/#{address}") do
        {:ok, %Req.Response{status: 200, body: %{"attributes" => attributes}}} ->
          {:ok,
           %{}
           |> put_present(:postal_code, attributes["POSTAL_CODE"])
           |> put_present(:city, attributes["CITY"])}

        {:ok, %Req.Response{status: 404}} ->
          {:error, :not_found}

        _other ->
          {:error, :unavailable}
      end
    else
      _error -> {:error, :unavailable}
    end
  end

  defp request(address, locale, location, api_key) do
    body = %{
      email: address,
      attributes: attributes(locale, location),
      listIds: list_ids(),
      updateEnabled: true
    }

    case Req.post(req(api_key), url: "/contacts", json: body) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        {:ok, :subscribed}

      {:ok, %Req.Response{status: 204}} ->
        {:ok, :subscribed}

      {:ok, %Req.Response{status: 400, body: %{"code" => "duplicate_parameter"}}} ->
        {:ok, :already_subscribed}

      _other ->
        {:error, :unavailable}
    end
  end

  defp attributes(locale, location) do
    %{"LANGUAGE" => language(locale), "COUNTRY" => "Canada"}
    |> put_present("POSTAL_CODE", location[:postal_code] || location["postal_code"])
    |> put_present("CITY", location[:city] || location["city"])
  end

  defp put_present(map, key, value) when is_binary(value) do
    case String.trim(value) do
      "" -> map
      present -> Map.put(map, key, present)
    end
  end

  defp put_present(map, _key, _value), do: map

  defp req(api_key) do
    Req.new(
      base_url: base_url(),
      headers: [{"api-key", api_key}, {"accept", "application/json"}],
      receive_timeout: 8_000,
      retry: false
    )
    |> Req.merge(Application.get_env(:pauseai_ca, :brevo_req_options, []))
  end

  defp validate_email(email) when is_binary(email) do
    trimmed = String.trim(email)

    if Regex.match?(~r/^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/, trimmed) do
      {:ok, trimmed}
    else
      {:error, :invalid_email}
    end
  end

  defp validate_email(_email), do: {:error, :invalid_email}

  defp api_key do
    case Application.get_env(:pauseai_ca, :brevo_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _unset -> {:error, :not_configured}
    end
  end

  defp list_ids do
    Application.get_env(:pauseai_ca, :brevo_list_ids, [])
  end

  defp base_url do
    Application.get_env(:pauseai_ca, :brevo_base_url, @brevo_base_url)
  end

  defp language("fr"), do: "French"
  defp language(_locale), do: "English"
end
