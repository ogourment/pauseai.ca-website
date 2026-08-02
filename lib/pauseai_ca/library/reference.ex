defmodule PauseAiCa.Library.Reference do
  @moduledoc """
  A single further reading, attached to a person or a topic.

  Smaller than `PauseAiCa.Library.Resource`: a reference is a pointer with a
  label, used where a reader wants more from the same person rather than a new
  stage of the argument.
  """

  @enforce_keys [:label, :url, :publisher, :language]
  defstruct [:label, :url, :publisher, :language]

  @type t :: %__MODULE__{
          label: %{String.t() => String.t()},
          url: String.t(),
          publisher: String.t(),
          language: String.t()
        }

  @doc """
  Returns the label for `locale`, falling back to English.
  """
  @spec label(t(), String.t()) :: String.t()
  def label(%__MODULE__{label: label}, locale) do
    Map.get(label, locale) || Map.fetch!(label, "en")
  end
end
