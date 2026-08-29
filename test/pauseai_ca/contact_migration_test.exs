defmodule PauseAiCa.ContactMigrationTest do
  use PauseAiCa.DataCase

  import PauseAiCa.AccountsFixtures

  alias PauseAiCa.ContactMigration

  test "imports only supplied rows, reconciles accounts, and records the actor" do
    actor = user_fixture()
    existing = user_fixture(%{email: "active@example.org"})

    rows = [
      %{
        "email" => existing.email,
        "name" => "Active Ada",
        "city" => "Montréal",
        "source_key" => "42",
        "status" => "known_active"
      },
      %{
        "email" => "review@example.org",
        "name" => "Review René",
        "city" => "Québec",
        "source_key" => "43",
        "status" => "",
        "notes" => "human-reviewed note"
      }
    ]

    assert {:ok, %{contacts: contacts}} =
             ContactMigration.import_selected(rows, "contacts.csv", "legacy-sheet", actor)

    assert length(contacts) == 2

    imported = Enum.find(contacts, &(&1.email == "review@example.org"))
    assert imported.source_data["notes"] == "human-reviewed note"

    [active] = ContactMigration.list_contacts("active@")
    assert active.user_id == existing.id
    assert active.classification == "known_active"

    [activity] = ContactMigration.list_activities(active.id)
    assert activity.actor_user_id == actor.id
    assert activity.details["account_match"]
  end

  test "reimport updates one contact without duplicating it and adds history" do
    actor = user_fixture()

    row = %{
      "email" => "same@example.org",
      "name" => "First",
      "city" => "",
      "source_key" => "1",
      "status" => ""
    }

    assert {:ok, _} = ContactMigration.import_selected([row], "one.csv", "sheet", actor)

    assert {:ok, _} =
             ContactMigration.import_selected(
               [%{row | "name" => "Updated"}],
               "two.csv",
               "sheet",
               actor
             )

    assert [contact] = ContactMigration.list_contacts("same@")
    assert contact.name == "Updated"
    assert length(ContactMigration.list_activities(contact.id)) == 2
  end
end
