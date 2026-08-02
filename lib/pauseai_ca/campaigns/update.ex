defmodule PauseAiCa.Campaigns.Update do
  @moduledoc """
  A single dated development in an ongoing campaign story.

  Every update links to reporting we did not write. We keep the canonical URL,
  the publisher, and the language the original was published in, and we write
  our own short summary rather than reproducing the source.
  """

  @enforce_keys [:date, :publisher, :language, :url, :copy]
  defstruct [:date, :publisher, :language, :url, :copy]

  @type locale :: String.t()

  @type t :: %__MODULE__{
          date: Date.t(),
          publisher: String.t(),
          language: locale(),
          url: String.t(),
          copy: %{locale() => %{title: String.t(), summary: String.t()}}
        }

  @doc """
  Returns the title and summary for `locale`, falling back to English.
  """
  @spec copy(t(), locale()) :: %{title: String.t(), summary: String.t()}
  def copy(%__MODULE__{copy: copy}, locale) do
    Map.get(copy, locale) || Map.fetch!(copy, "en")
  end

  @doc """
  True when the linked article is not in the reader's language, so the page can
  tell them before they follow the link.
  """
  @spec foreign_language?(t(), locale()) :: boolean()
  def foreign_language?(%__MODULE__{language: language}, locale), do: language != locale
end
