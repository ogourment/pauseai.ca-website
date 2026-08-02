defmodule PauseAiCa.Library.Voice do
  @moduledoc """
  A Canadian voice on advanced AI risk, with a short attributed quotation.

  Canada holds an unusual share of the field's founders and of its most
  prominent critics. Naming them is the point: a visitor who thinks this is a
  fringe worry should recognize the people saying it, and should be able to
  reach the original in one click.

  Quotations are kept short and attributed, and every entry links to the source.
  """

  @enforce_keys [:id, :name, :affiliation, :url, :source, :reviewed_on, :quote]
  defstruct [:id, :name, :affiliation, :url, :source, :reviewed_on, :quote, :note]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          affiliation: %{String.t() => String.t()},
          url: String.t(),
          source: String.t(),
          reviewed_on: Date.t(),
          quote: %{String.t() => String.t()},
          note: %{String.t() => String.t()} | nil
        }

  @doc """
  Returns the value of `field` for `locale`, falling back to English.
  """
  @spec text(t(), :quote | :affiliation | :note, String.t()) :: String.t() | nil
  def text(%__MODULE__{} = voice, field, locale) do
    case Map.fetch!(voice, field) do
      nil -> nil
      map -> Map.get(map, locale) || Map.get(map, "en")
    end
  end
end
