defmodule PauseAiCa.Donations.InteracDeclaration do
  @moduledoc "Private Interac declarations and separately attributed bank receipt verification."
  use PhoenixDonations.DeclarationSchema,
    table: "interac_declarations",
    account_ref_type: :binary_id
end
