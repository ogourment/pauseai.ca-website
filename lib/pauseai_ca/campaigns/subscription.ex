defmodule PauseAiCa.Campaigns.Subscription do
  @moduledoc """
  Subscribes a supporter to the PauseAI Canada mailing list in Brevo.

  Brevo, not our database, is the record for people who ask for updates. That
  keeps one copy of an email address under one set of unsubscribe and retention
  controls rather than two.

  We send the address, the language they read the site in, and the country. We
  do not send anything they did not type, and the caller must have taken an
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
  @spec subscribe(String.t(), String.t()) ::
          {:ok, :subscribed | :already_subscribed}
          | {:error, :invalid_email | :not_configured | :unavailable}
  def subscribe(email, locale) do
    with {:ok, address} <- validate_email(email),
         {:ok, api_key} <- api_key() do
      request(address, locale, api_key)
    end
  end

  defp request(address, locale, api_key) do
    body = %{
      email: address,
      attributes: %{"LANGUAGE" => language(locale), "COUNTRY" => "Canada"},
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
