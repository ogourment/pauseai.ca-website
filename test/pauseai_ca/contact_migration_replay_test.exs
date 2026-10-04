defmodule PauseAiCa.ContactMigrationReplayTest do
  use PauseAiCa.DataCase
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{ContactMigration, CRM, Volunteers, Repo}
  alias PauseAiCa.Accounts.{Scope, User}
  alias PauseAiCa.ContactMigration.{Contact, Activity, Import}
  alias PauseAiCa.CRM.ContactLink

  setup do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    assert_receive {:email, _}
    %{admin: admin, scope: Scope.for_user(admin)}
  end

  defp row(number) do
    %{
      "email" => "replay-#{number}@example.org",
      "name" => "Source #{number}",
      "city" => "Montréal",
      "source_key" => "tab:#{number}",
      "status" => "needs_review",
      "signup_date" => "2025-12-28",
      "sheet" => "mtl",
      "snapshot" => "snapshot-a",
      "row" => number,
      "first_seen_precision" => "date"
    }
  end

  test "replay retains corrections, withdrawal, identity and both raw observations", c do
    accounts = Repo.aggregate(User, :count)

    assert {:ok, %{contacts: [original], import: first}} =
             ContactMigration.import_selected([row(2)], "first.csv", "sheet", c.admin)

    link = Repo.get_by!(ContactLink, contact_id: original.id)
    assert {:ok, person} = CRM.get(c.scope, link.person_id)

    assert {:ok, corrected_person} =
             CRM.update(c.scope, person, %{"name" => "Human name", "city" => "Québec"})

    recovered =
      Jason.encode!(%{
        "events" => [
          %{
            "kind" => "source_created",
            "value" => "2025-12-28T14:30:00Z",
            "precision" => "datetime",
            "source" => "original-notification"
          }
        ]
      })

    original
    |> Ecto.Changeset.change(
      name: "Human name",
      city: "Québec",
      classification: "do_not_contact",
      source_data: Map.put(original.source_data, "historical_dates", recovered)
    )
    |> Repo.update!()

    changed =
      Map.merge(row(2), %{
        "name" => "Revised source",
        "city" => "Ottawa",
        "status" => "known_active",
        "snapshot" => "snapshot-b",
        "signup_date" => "2026-01-01"
      })

    assert {:ok, %{contacts: [replayed], import: second}} =
             ContactMigration.import_selected([changed], "second.csv", "sheet", c.admin)

    assert replayed.id == original.id
    assert replayed.name == "Human name"
    assert replayed.city == "Québec"
    assert replayed.classification == "do_not_contact"
    assert replayed.source_data["historical_dates"] == recovered
    assert replayed.inserted_at == original.inserted_at
    assert {:ok, still_corrected} = CRM.get(c.scope, link.person_id)
    assert still_corrected.person.id == corrected_person.person.id
    assert still_corrected.person.name == "Human name"
    assert Repo.aggregate(Contact, :count) == 1
    assert Repo.aggregate(User, :count) == accounts
    assert Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count) == 0

    observations =
      Repo.all(from a in Activity, where: a.contact_id == ^original.id, order_by: a.id)

    assert length(observations) == 2
    assert Enum.any?(observations, &(&1.details["source_data"]["snapshot"] == "snapshot-a"))
    assert Enum.any?(observations, &(&1.details["source_data"]["snapshot"] == "snapshot-b"))
    assert Enum.all?(observations, &(&1.actor_user_id == c.admin.id))
    assert Enum.all?(observations, &(&1.details["source_data"]["row"] == 2))

    assert Enum.all?(
             observations,
             &(not Map.has_key?(&1.details["source_data"], "first_created_at"))
           )

    for receipt <- [first, second] do
      assert {:ok, %{entries: [%{id: id}], total: 1}} =
               ContactMigration.contacts_page(c.scope, "replay", 1, 25, receipt.id)

      assert id == original.id
    end
  end

  test "source withdrawal overrides active classification; changed address or duplicate stable key refuses atomically",
       c do
    {:ok, %{contacts: [original]}} =
      ContactMigration.import_selected([row(3)], "a.csv", "sheet", c.admin)

    {:ok, %{contacts: [withdrawn]}} =
      ContactMigration.import_selected(
        [Map.put(row(3), "status", "do_not_contact")],
        "b.csv",
        "sheet",
        c.admin
      )

    assert withdrawn.classification == "do_not_contact"
    counts = {Repo.aggregate(Import, :count), Repo.aggregate(Activity, :count)}

    assert {:error, :contacts, :source_identity_conflict, _} =
             ContactMigration.import_selected(
               [Map.put(row(3), "email", "changed@example.org")],
               "c.csv",
               "sheet",
               c.admin
             )

    assert Repo.get!(Contact, original.id).email == original.email
    assert {Repo.aggregate(Import, :count), Repo.aggregate(Activity, :count)} == counts
  end

  test "receipt pagination remains scoped and revoked/non-admin access leaves no state", c do
    {:ok, %{import: first}} =
      ContactMigration.import_selected(Enum.map(1..12, &row/1), "a.csv", "sheet", c.admin)

    {:ok, _} = ContactMigration.import_selected([row(20), row(1)], "b.csv", "sheet", c.admin)

    assert {:ok, %{entries: entries, pages: 2, total: 12, page: 2}} =
             ContactMigration.contacts_page(c.scope, "", 2, 10, first.id)

    assert length(entries) == 2

    assert {:ok, %{total: 1}} =
             ContactMigration.contacts_page(c.scope, "replay-1@", 1, 10, first.id)

    assert {:ok, %{total: 0}} =
             ContactMigration.contacts_page(c.scope, "replay-20@", 1, 10, first.id)

    before =
      {Repo.aggregate(Import, :count), Repo.aggregate(Contact, :count),
       Repo.aggregate(Activity, :count)}

    c.admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert not Volunteers.superadmin?(c.scope)
    assert {:error, :unauthorized} = ContactMigration.contacts_page(c.scope, "", 1, 25, first.id)
    assert ContactMigration.receipts(c.scope) == []

    assert {:error, :actor, :unauthorized, _} =
             ContactMigration.import_selected([row(30)], "denied.csv", "sheet", c.admin)

    assert {Repo.aggregate(Import, :count), Repo.aggregate(Contact, :count),
            Repo.aggregate(Activity, :count)} == before

    refute_receive {:email, _}
  end
end
