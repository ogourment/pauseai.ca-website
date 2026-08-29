defmodule PauseAiCa.ContactMigration.CSVTest do
  use ExUnit.Case, async: true

  alias PauseAiCa.ContactMigration.CSV

  test "parses quoted fields and reports additional preserved columns" do
    csv =
      "email,name,city,private note\nactive@example.org,\"Active, Ada\",Montréal,do not copy\n"

    assert {:ok, [row], ["private_note"]} = CSV.parse(csv)
    assert row["email"] == "active@example.org"
    assert row["name"] == "Active, Ada"
    assert row["valid"]
  end

  test "requires an email column and identifies invalid addresses" do
    assert {:error, :missing_email} = CSV.parse("name,city\nAda,Montréal\n")
    assert {:ok, [row], []} = CSV.parse("email\nnot-an-email\n")
    refute row["valid"]
  end

  test "recognizes every standard and Montreal production-sheet column" do
    csv = File.read!("test/fixtures/contact_import_review.csv")

    assert {:ok, [row | _], []} = CSV.parse(csv)
    assert row["discord_user_id"] == "10001"
    assert row["skills_interests"] == "Facilitation"
    assert row["meetups_attended"] == "2"
  end
end
