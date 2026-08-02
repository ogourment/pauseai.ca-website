defmodule PauseAiCa.Campaigns.Representative do
  @moduledoc """
  A federal member of parliament matched to a visitor's postal code.
  """

  @enforce_keys [:name, :district, :email]
  defstruct [:name, :district, :email, :party, :profile_url]

  @type t :: %__MODULE__{
          name: String.t(),
          district: String.t(),
          email: String.t(),
          party: String.t() | nil,
          profile_url: String.t() | nil
        }
end
