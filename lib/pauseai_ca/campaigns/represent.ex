defmodule PauseAiCa.Campaigns.Represent do
  @moduledoc """
  Looks up federal members of parliament by postal code.

  Backed by Open North's Represent API, which is a public read-only service. We
  send only the postal code the visitor typed, and we store nothing.
  """

  alias PauseAiCa.Campaigns.Representative

  @default_base_url "https://represent.opennorth.ca"
  @house_of_commons "House of Commons"

  @doc """
  Normalizes a Canadian postal code to the compact `A1A1A1` form.

  Returns `{:ok, code}` or `:error` when the input cannot be a postal code.
  """
  @spec normalize_postal_code(String.t()) :: {:ok, String.t()} | :error
  def normalize_postal_code(input) when is_binary(input) do
    compact =
      input
      |> String.upcase()
      |> String.replace(~r/[^A-Z0-9]/, "")

    if Regex.match?(~r/^[ABCEGHJ-NPRSTVXY][0-9][A-Z][0-9][A-Z][0-9]$/, compact) do
      {:ok, compact}
    else
      :error
    end
  end

  def normalize_postal_code(_input), do: :error

  @doc """
  Returns the members of parliament whose district contains `postal_code`.

  Returns `{:error, :invalid_postal_code}` for input that is not a postal code,
  `{:error, :not_found}` when the service knows no such code, and
  `{:error, :unavailable}` when the service cannot be reached.
  """
  @spec members_of_parliament(String.t()) ::
          {:ok, [Representative.t()]} | {:error, :invalid_postal_code | :not_found | :unavailable}
  def members_of_parliament(postal_code) do
    with {:ok, code} <- normalize_postal_code(postal_code),
         {:ok, payload} <- get_postcode(code) do
      {:ok, extract_members(payload)}
    else
      :error -> {:error, :invalid_postal_code}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_postcode(code) do
    case Req.get(request(), url: "/postcodes/#{code}/") do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      _other -> {:error, :unavailable}
    end
  end

  defp request do
    Req.new(base_url: base_url(), receive_timeout: 8_000, retry: false)
    |> Req.merge(Application.get_env(:pauseai_ca, :represent_req_options, []))
  end

  defp base_url do
    Application.get_env(:pauseai_ca, :represent_base_url, @default_base_url)
  end

  @doc """
  Builds representatives from a Represent postcode payload.

  Exposed so the shape of the upstream response can be tested without a network
  call.
  """
  @spec extract_members(map()) :: [Representative.t()]
  def extract_members(payload) do
    payload
    |> Map.get("representatives_centroid", [])
    |> List.wrap()
    |> Enum.filter(&house_of_commons?/1)
    |> Enum.map(&to_representative/1)
    |> Enum.reject(&(&1.email in [nil, ""]))
  end

  defp house_of_commons?(%{"representative_set_name" => @house_of_commons}), do: true
  defp house_of_commons?(_representative), do: false

  defp to_representative(representative) do
    %Representative{
      name: representative["name"],
      district: representative["district_name"],
      email: representative["email"],
      party: blank_to_nil(representative["party_name"]),
      profile_url: blank_to_nil(representative["url"]),
      preferred_languages:
        preferred_languages(get_in(representative, ["extra", "preferred_languages"]))
    }
  end

  defp preferred_languages(values) do
    values
    |> List.wrap()
    |> Enum.flat_map(fn value ->
      normalized = value |> to_string() |> String.downcase()

      []
      |> maybe_add_language(:en, String.contains?(normalized, "english"))
      |> maybe_add_language(:fr, String.contains?(normalized, "french"))
    end)
    |> Enum.uniq()
  end

  defp maybe_add_language(languages, language, true), do: languages ++ [language]
  defp maybe_add_language(languages, _language, false), do: languages

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
