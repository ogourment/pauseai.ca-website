defmodule PauseAiCaWeb.InteracParameterPrivacyTest do
  use ExUnit.Case, async: true

  test "public declarations and private bank matching are filtered from parameter logs" do
    params = %{
      "interac" => %{
        "name" => "Synthetic Donor",
        "email" => "donor@example.test",
        "amount" => "25.00"
      },
      "verification" => %{
        "bank_reference" => "BANK-PRIVATE",
        "verification_note" => "Private bank note"
      },
      "locale" => "fr"
    }

    assert Phoenix.Logger.filter_values(params) == %{
             "interac" => "[FILTERED]",
             "verification" => "[FILTERED]",
             "locale" => "fr"
           }
  end
end
