defmodule PauseAiCaWeb.LegacyCRMUpgradeLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, CRM, ContactMigration}

  test "upgrade exposes fourteen pre-CRM contacts without changing their history or outreach state",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    account = user_fixture(%{email: "old-bulk-1@example.org"})

    contacts =
      for n <- 1..14 do
        %ContactMigration.Contact{
          email: "old-bulk-#{n}@example.org",
          name: "Stored contact #{n}",
          source: "historical-sheet",
          source_key: "row:#{n}",
          city: "Montréal",
          source_data: %{"signup_date" => "45945", "notes" => "Retained source note"},
          classification: if(n == 1, do: "do_not_contact", else: "needs_review"),
          user_id: if(n == 1, do: account.id)
        }
        |> Repo.insert!()
      end

    original = Repo.all(ContactMigration.Contact)
    before_accounts = Repo.all(PauseAiCa.Accounts.User)
    scope = PauseAiCa.Accounts.Scope.for_user(admin)
    assert {:ok, %{total: 0}} = CRM.directory_page(scope, %{})
    assert {:ok, 14} = CRM.LegacyUpgrade.run(Repo)
    assert {:ok, %{total: 14}} = CRM.directory_page(scope, %{})

    {:ok, view, _} =
      live(log_in_user(conn, admin), ~p"/admin/contacts?locale=en&q=old-bulk&per=10")

    assert has_element?(view, "#crm-pagination", "14 contacts")
    assert has_element?(view, "dd", "2025-10-15")
    [first | _] = contacts

    {:ok, profile, _} =
      live(log_in_user(conn, admin), ~p"/admin/contacts/legacy/#{first.id}?locale=en")

    assert has_element?(profile, "#crm-origins", "do_not_contact")
    assert has_element?(profile, "#crm-source-details", "Retained source note")
    assert Repo.all(ContactMigration.Contact) == original
    assert Repo.all(PauseAiCa.Accounts.User) == before_accounts
    assert Repo.aggregate(ContactMigration.Import, :count) == 0
    assert Repo.aggregate(ContactMigration.Activity, :count) == 0
    assert Repo.aggregate(PhoenixCRM.Person, :count) == 14
    assert Repo.aggregate(PauseAiCa.CRM.ContactLink, :count) == 14
    assert Enum.all?(Repo.all(PhoenixCRM.Activity), &(&1.actor_id == "migration:20261005045000"))
    assert {:ok, 0} = CRM.LegacyUpgrade.run(Repo)
    assert Repo.aggregate(PhoenixCRM.Activity, :count) == 14
    assert Repo.aggregate(PauseAiCa.Mail.Batch, :count) == 0
    assert Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count) == 0
  end
end
