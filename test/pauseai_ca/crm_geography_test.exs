defmodule PauseAiCa.CRMGeographyTest do
  use PauseAiCa.DataCase
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{CRM, ContactMigration, Repo}
  alias PauseAiCa.Accounts.{Scope, User}
  alias PauseAiCa.CRM.Geography

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    %{admin: admin, scope: Scope.for_user(admin)}
  end

  defp person(scope, email, city), do: CRM.create(scope, %{email: email, name: email, city: city})

  test "standalone contacts match city province and explicit area while an edit replaces old city",
       c do
    {:ok, record} = person(c.scope, "standalone@example.org", "Toronto")

    assert {:ok, %{total: 1, records: [row]}} =
             CRM.directory_page(c.scope, %{"provinces" => ["ON"]})

    assert row.person.id == record.person.id and row.geography.city == "Toronto"
    assert {:ok, %{total: 1}} = CRM.directory_page(c.scope, %{"areas" => ["toronto_gta"]})
    assert {:ok, %{total: 1}} = CRM.directory_page(c.scope, %{"cities" => ["Toronto"]})
    {:ok, updated} = CRM.update(c.scope, record, %{city: "Vancouver"})
    assert updated.person.city == "Vancouver"
    assert {:ok, %{total: 0}} = CRM.directory_page(c.scope, %{"provinces" => ["ON"]})
    assert {:ok, %{total: 1}} = CRM.directory_page(c.scope, %{"cities" => ["Vancouver"]})
    assert {:ok, %{total: 1}} = CRM.directory_page(c.scope, %{"provinces" => ["BC"]})
  end

  test "current canonical city wins broad legacy data and original geography is preserved", c do
    row = %{
      "email" => "legacy@example.org",
      "city" => "Toronto",
      "sheet" => "Rest of Canada",
      "fsa" => "M5V"
    }

    {:ok, %{contacts: [contact]}} =
      ContactMigration.import_selected([row], "synthetic.csv", "geo", c.admin)

    {:ok, record} = CRM.get_legacy(c.scope, contact.id)
    raw_before = Repo.get!(ContactMigration.Contact, contact.id).source_data
    assert {:ok, %{total: 1}} = CRM.directory_page(c.scope, %{"provinces" => ["Ontario"]})
    assert {:ok, %{total: 1}} = CRM.directory_page(c.scope, %{"fsas" => "m5v"})
    {:ok, _} = CRM.update(c.scope, record, %{city: "Vancouver"})
    assert {:ok, %{total: 0}} = CRM.directory_page(c.scope, %{"cities" => ["Toronto"]})
    assert {:ok, %{total: 0}} = CRM.directory_page(c.scope, %{"fsas" => "M5V"})

    assert {:ok, %{total: 1, records: [current]}} =
             CRM.directory_page(c.scope, %{"cities" => ["Vancouver"]})

    assert current.geography.subdivision == "BC"
    assert Repo.get!(ContactMigration.Contact, contact.id).source_data == raw_before
  end

  test "province-only and unknown observations never imply a city; Vancouver is not its metro",
       c do
    for {email, attrs} <- [
          {"ontario@example.org", %{province: "Ontario"}},
          {"broad@example.org", %{region: "ROCanada"}},
          {"postal@example.org", %{fsa: "M5V 3A8"}},
          {"burnaby@example.org", %{city: "Burnaby", province: "BC"}}
        ] do
      assert {:ok, _} =
               CRM.observe(
                 c.scope,
                 Map.merge(%{email: email, name: email}, attrs),
                 "synthetic",
                 email
               )
    end

    assert {:ok, %{total: 2}} = CRM.directory_page(c.scope, %{"provinces" => ["ON"]})

    assert {:ok, %{total: 0}} =
             CRM.directory_page(c.scope, %{"cities" => ["Toronto", "Vancouver"]})

    assert {:ok, %{total: 0}} = CRM.directory_page(c.scope, %{"areas" => ["toronto_gta"]})

    assert {:ok, %{total: 1, records: [unknown]}} =
             CRM.directory_page(c.scope, %{"unknown" => "true"})

    assert unknown.geography.city == nil and unknown.geography.subdivision == nil
    assert {:ok, %{total: 1}} = CRM.directory_page(c.scope, %{"fsas" => "M5V"})
  end

  test "OR overlap aliases page totals and all-row selection share the same canonical projection",
       c do
    for n <- 1..12, do: person(c.scope, "toronto-#{n}@example.org", "Toronto")
    {:ok, _} = person(c.scope, "vancouver@example.org", "Vancouver")
    {:ok, _} = person(c.scope, "unknown@example.org", nil)
    params = %{"provinces" => ["Ontario"], "cities" => ["Toronto"], "per" => "10", "page" => "2"}
    assert {:ok, %{total: 12, pages: 2, records: rows}} = CRM.directory_page(c.scope, params)
    assert length(rows) == 2

    assert {:ok, %{total: 12, records: all}} =
             CRM.directory_page(c.scope, Map.put(params, :all_rows, true))

    assert length(all) == 12 and length(Enum.uniq_by(all, & &1.person.id)) == 12

    assert {:ok, %{total: 13}} =
             CRM.directory_page(c.scope, %{"provinces" => ["ON"], "cities" => ["Vancouver"]})

    assert Geography.filters(%{"cities" => ["Scarborough"]})["cities"] == ["Toronto"]
  end

  test "merged aliases count once and geography reads change no subscription source or authority",
       c do
    {:ok, first} =
      CRM.create(c.scope, %{email: "alias-a@example.org", name: "Same person", city: "Toronto"})

    {:ok, second} =
      CRM.create(c.scope, %{email: "alias-b@example.org", name: "Same person", city: "Toronto"})

    {:ok, comparison} = CRM.compare(c.scope, first.person.id, second.person.id)
    {:ok, _} = CRM.merge(c.scope, comparison, %{"preferred_address_id" => hd(first.addresses).id})

    before =
      {Repo.aggregate(User, :count), Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count),
       Repo.aggregate(PhoenixCRM.Activity, :count)}

    assert {:ok, %{total: 1, records: [record]}} =
             CRM.directory_page(c.scope, %{"provinces" => ["ON"], "areas" => ["toronto_gta"]})

    assert length(record.addresses) == 2

    assert before ==
             {Repo.aggregate(User, :count),
              Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count),
              Repo.aggregate(PhoenixCRM.Activity, :count)}

    Repo.update!(change(c.admin, superadmin: false))
    assert {:error, :unauthorized} = CRM.directory_page(c.scope, %{"provinces" => ["ON"]})
  end

  test "foreign Ontario stays a city without Canadian inference and broad canonical buckets yield to a source city",
       c do
    {:ok, foreign} =
      CRM.observe(
        c.scope,
        %{
          email: "ontario-us@example.org",
          city: "Ontario",
          country: "US",
          province: "ON",
          fsa: "M5V"
        },
        "synthetic",
        "foreign"
      )

    {:ok, broad} =
      CRM.observe(
        c.scope,
        %{email: "broad-city@example.org", city: "Toronto"},
        "synthetic",
        "broad-city"
      )

    {:ok, _} = CRM.update(c.scope, broad, %{city: "ROCanada"})

    assert {:ok, %{total: 1, records: [record]}} =
             CRM.directory_page(c.scope, %{"provinces" => ["ON"]})

    assert record.person.id == broad.person.id and record.geography.city == "Toronto"
    assert {:ok, %{records: records}} = CRM.directory_page(c.scope, %{})
    other = Enum.find(records, &(&1.person.id == foreign.person.id))
    assert other.geography.city == "Ontario"
    assert other.geography.subdivision == nil and other.geography.postal_area == nil
    assert {:ok, persisted} = CRM.get(c.scope, broad.person.id)
    assert persisted.person.city == "ROCanada"
  end
end
