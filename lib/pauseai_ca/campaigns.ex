defmodule PauseAiCa.Campaigns do
  @moduledoc """
  The Campaigns context.

  A campaign is a time-bounded public call to act on a specific, verifiable
  event. It holds reviewed editorial content, the developments that followed,
  and the tools a visitor needs to contact their member of parliament.

  Nothing in this context reads or writes the database. Postal codes are used
  for a single lookup and are never stored.
  """

  alias PauseAiCa.Campaigns.Letter
  alias PauseAiCa.Campaigns.Represent
  alias PauseAiCa.Campaigns.Representative
  alias PauseAiCa.Campaigns.WarningShot

  @doc """
  Returns the Warning Shot activation that is currently running.
  """
  @spec current_warning_shot() :: WarningShot.t()
  defdelegate current_warning_shot(), to: WarningShot, as: :current

  @doc """
  Finds the members of parliament for a Canadian postal code.
  """
  @spec find_members_of_parliament(String.t()) ::
          {:ok, [Representative.t()]} | {:error, :invalid_postal_code | :not_found | :unavailable}
  defdelegate find_members_of_parliament(postal_code), to: Represent, as: :members_of_parliament

  @doc """
  Composes an editable letter for the given representatives.
  """
  @spec compose_letter([Representative.t()], Letter.draft_language(), map()) :: Letter.t()
  defdelegate compose_letter(representatives, language, sender), to: Letter, as: :compose
end
