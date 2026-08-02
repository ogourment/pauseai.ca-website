defmodule PauseAiCa.Library.Voice do
  @moduledoc """
  Someone working in Canada who has said something on the record about advanced
  AI risk, with what they actually said and where to check it.

  Every quotation is verbatim from a linked source. Where a claim about a person
  is contested — Geoffrey Hinton, for instance, has publicly rejected the
  "quit Google to warn the world" story that circulated about him — we quote him
  instead of narrating him.
  """

  alias PauseAiCa.Library.Reference

  @enforce_keys [:id, :name, :affiliation, :quotes, :references]
  defstruct [:id, :name, :affiliation, :quotes, :references]

  @type quotation :: %{
          text: %{String.t() => String.t()},
          source: String.t(),
          url: String.t(),
          said_on: String.t() | nil,
          language: String.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          affiliation: %{String.t() => String.t()},
          quotes: [quotation()],
          references: [Reference.t()]
        }

  @doc """
  Returns the affiliation line for `locale`, falling back to English.
  """
  @spec affiliation(t(), String.t()) :: String.t()
  def affiliation(%__MODULE__{affiliation: affiliation}, locale) do
    Map.get(affiliation, locale) || Map.fetch!(affiliation, "en")
  end

  @doc """
  Returns the text of `quotation` for `locale`.

  A quotation given in English stays in English even for a French reader: a
  translated quotation is no longer a quotation. The template marks the language
  so the reader knows before they start.
  """
  @spec quote_text(quotation(), String.t()) :: String.t()
  def quote_text(quotation, locale) do
    Map.get(quotation.text, locale) || Map.fetch!(quotation.text, quotation.language)
  end
end
