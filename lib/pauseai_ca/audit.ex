defmodule PauseAiCa.Audit do
  @moduledoc """
  Structured logging of what people do on the site.

  Logs are operational evidence — did the letter go, is the lookup failing, is
  something being abused — and they are also the easiest place to leak
  supporter data by accident. So this module is the only place that writes
  them, and it will not accept an email address, a postal code or a letter body.

  Identities are recorded as a short salted digest. That is enough to see that
  one person sent three letters, and not enough to learn who they are from the
  log alone. The salt lives in `SECRET_KEY_BASE`, so logs shipped off the box
  cannot be correlated back without it.

  Events are emitted at `:info` so they survive a production log level that
  filters debug noise.
  """

  require Logger

  @doc """
  Records `event` with `metadata`.

  Any `:email` key is digested into `:actor`. Keys known to carry personal data
  are dropped rather than trusted to the caller.
  """
  @spec event(atom(), map()) :: :ok
  def event(event, metadata \\ %{}) do
    metadata =
      metadata
      |> digest_actor()
      |> Map.drop([:email, :postal_code, :body, :subject, :name, :recipients, :to])

    Logger.info("pauseai.#{event} #{format(metadata)}", Map.to_list(metadata) ++ [event: event])
  end

  @doc """
  A short, stable, non-reversible handle for a person.

  Exposed so callers can correlate without ever holding the address.
  """
  @spec actor(String.t() | nil) :: String.t()
  def actor(nil), do: "anonymous"

  def actor(email) when is_binary(email) do
    :crypto.mac(:hmac, :sha256, salt(), String.downcase(String.trim(email)))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp digest_actor(%{email: email} = metadata) when is_binary(email) do
    metadata |> Map.put(:actor, actor(email)) |> Map.delete(:email)
  end

  defp digest_actor(metadata), do: metadata

  defp format(metadata) do
    Enum.map_join(metadata, " ", fn {key, value} -> "#{key}=#{inspect(value)}" end)
  end

  defp salt do
    Application.get_env(:pauseai_ca, PauseAiCaWeb.Endpoint)[:secret_key_base] || "dev-salt"
  end
end
