defmodule PauseAiCa.Environment do
  @moduledoc """
  Which deployment this is, for the benefit of anyone looking at the screen.

  Staging now looks exactly like production will, which is precisely when
  someone edits the wrong thing or reports a bug against the wrong site. So
  every non-production deployment says so, in the header and on the browser tab.

  Reads `PAUSEAI_CA_DISPLAY_ENV`, which the blue/green deploy already sets.
  """

  @doc "The label to show, or nil in production."
  @spec label() :: String.t() | nil
  def label do
    case Application.get_env(:pauseai_ca, :display_env) do
      nil -> nil
      "" -> nil
      "prod" -> nil
      "production" -> nil
      other -> other |> to_string() |> String.upcase()
    end
  end

  @doc "True when this deployment is not production."
  @spec badged?() :: boolean()
  def badged?, do: not is_nil(label())

  @doc """
  The favicon for this deployment, with a cache-busting digest.

  A different tab icon is the fastest way to tell two identical-looking sites
  apart in a row of open tabs — but only if the browser fetches the new one.
  Favicons are cached hard, so this goes through the endpoint's static path to
  pick up the content hash and change whenever the file does.
  """
  @spec favicon_path() :: String.t()
  def favicon_path do
    PauseAiCaWeb.Endpoint.static_path(favicon_file())
  end

  defp favicon_file do
    case label() do
      nil -> "/images/favicon.svg"
      "STAGING" -> "/images/favicon-staging.svg"
      _other -> "/images/favicon-dev.svg"
    end
  end
end
