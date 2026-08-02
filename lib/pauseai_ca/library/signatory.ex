defmodule PauseAiCa.Library.Signatory do
  @moduledoc """
  A Canadian parliamentarian who signed the ControlAI Canada statement calling
  for an international agreement to prohibit superintelligent AI.

  This exists because "politicians don't care about this" is the most common
  reason people give for not writing to their MP. Sixteen of them, from every
  party and both chambers, have already put their name to it.
  """

  @enforce_keys [:name, :chamber, :party]
  defstruct [:name, :chamber, :party, :note]

  @type t :: %__MODULE__{
          name: String.t(),
          chamber: :commons | :senate,
          party: %{String.t() => String.t()},
          note: %{String.t() => String.t()} | nil
        }

  @doc "Returns the party label for `locale`, falling back to English."
  @spec party(t(), String.t()) :: String.t()
  def party(%__MODULE__{party: party}, locale) do
    Map.get(party, locale) || Map.fetch!(party, "en")
  end

  @doc "Returns the note for `locale`, or nil."
  @spec note(t(), String.t()) :: String.t() | nil
  def note(%__MODULE__{note: nil}, _locale), do: nil
  def note(%__MODULE__{note: note}, locale), do: Map.get(note, locale) || Map.get(note, "en")
end
