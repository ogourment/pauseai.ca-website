defmodule PauseAiCa.Library.Resource do
  @moduledoc """
  A reviewed link to material someone else published.

  We do not copy or translate third-party work. Each entry records where it came
  from, who published it, what language it is in, and when a person last checked
  that it still says what we claim it says. The summary is ours.
  """

  @enforce_keys [:id, :stage, :format, :language, :url, :publisher, :reviewed_on, :copy]
  defstruct [
    :id,
    :stage,
    :format,
    :language,
    :url,
    :publisher,
    :author,
    :reviewed_on,
    :copy,
    canadian: false
  ]

  @type stage :: :curiosity | :risk | :responses | :coordination | :agency | :participation
  @type format :: :article | :video | :report | :testimony | :faq | :organization

  @type t :: %__MODULE__{
          id: String.t(),
          stage: stage(),
          format: format(),
          language: String.t(),
          url: String.t(),
          publisher: String.t(),
          author: String.t() | nil,
          reviewed_on: Date.t(),
          canadian: boolean(),
          copy: %{String.t() => %{title: String.t(), summary: String.t()}}
        }

  @doc """
  Returns the title and summary for `locale`, falling back to English.
  """
  @spec copy(t(), String.t()) :: %{title: String.t(), summary: String.t()}
  def copy(%__MODULE__{copy: copy}, locale) do
    Map.get(copy, locale) || Map.fetch!(copy, "en")
  end

  @doc """
  True when the resource is not published in the reader's language.
  """
  @spec foreign_language?(t(), String.t()) :: boolean()
  def foreign_language?(%__MODULE__{language: language}, locale), do: language != locale
end
