defmodule PauseAiCa.ContactMigrationTest do
  use PauseAiCa.DataCase

  import PauseAiCa.AccountsFixtures

  alias PauseAiCa.ContactMigration

  test "imports only supplied rows, reconciles accounts, and records the actor" do
    actor =
      user_fixture()
      |> Ecto.Changeset.change(superadmin: true, confirmed_at: DateTime.utc_now(:second))
      |> PauseAiCa.Repo.update!()

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

  test "full form answers survive import and replay without enrollment or outreach" do
    actor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> PauseAiCa.Repo.update!()

    row = %{
      "email" => "profile-evidence@example.org",
      "name" => "Synthetic profile",
      "source_key" => "gmail/synthetic-stable-message",
      "signup_date" => "2025-07-16",
      "intent" => "Volunteer",
      "weekly_hours" => "2–5",
      "skills_interests" => "Research",
      "skills_other" => "Translation",
      "languages" => "English, French",
      "bio" => "Synthetic bio",
      "motivation" => "Research",
      "discovery" => "Friend",
      "email_subscription" => "No",
      "source_message_id" => "synthetic-stable-message"
    }

    before_users = PauseAiCa.Repo.aggregate(PauseAiCa.Accounts.User, :count)

    for _ <- 1..2 do
      assert {:ok, %{contacts: [contact]}} =
               ContactMigration.import_selected(
                 [row],
                 "full-profile.csv",
                 "global-registration",
                 actor
               )

      for key <-
            ~w(intent weekly_hours skills_interests skills_other languages bio motivation discovery email_subscription source_message_id signup_date),
          do: assert(contact.source_data[key] == row[key])
    end

    assert length(ContactMigration.list_contacts("profile-evidence@")) == 1
    assert PauseAiCa.Repo.aggregate(PauseAiCa.Accounts.User, :count) == before_users
    assert PauseAiCa.Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
    assert PauseAiCa.Repo.aggregate(PauseAiCa.Newsletters.Batch, :count) == 0
    assert PauseAiCa.Repo.aggregate(PauseAiCa.Newsletters.Delivery, :count) == 0
  end

  test "reimport updates one contact without duplicating it and adds history" do
    actor =
      user_fixture()
      |> Ecto.Changeset.change(superadmin: true, confirmed_at: DateTime.utc_now(:second))
      |> PauseAiCa.Repo.update!()

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
