defmodule PauseAiCa.ContactGeographyTest do
  use PauseAiCa.DataCase
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, CRM, ContactMigration}
  alias PauseAiCa.Accounts.Scope
  require Phoenix.LiveViewTest
  alias PauseAiCa.ContactMigration.Geography

  test "Montreal city fills geography while explicit region and sheet take precedence" do
    for city <- ["Montreal", "Montréal", "  MONTREAL "] do
      assert Geography.resolve(%{"city" => city}) == {"Montréal", "city"}
    end

    assert Geography.resolve(%{"city" => "Montreal", "region" => "ROQuébec"}) ==
             {"ROQuébec", "source"}

    assert Geography.resolve(%{"city" => "Montreal", "sheet" => "rest of canada"}) ==
             {"ROCanada", "sheet"}

    assert Geography.resolve(%{"city" => "Toronto"}) == {nil, nil}

    rows = [
      %{"city" => "Montreal"},
      %{"geography" => "ROQuébec"},
      %{"email" => "synthetic@example.org"}
    ]

    assert {:ok, [one, two, three]} = Geography.with_default(rows, "ROCanada")
    assert one == hd(rows) and two == Enum.at(rows, 1)
    assert three["geography"] == "ROCanada" and three["region_source"] == "upload_default"
    assert {:error, :invalid_geography} = Geography.with_default(rows, "invalid")
  end

  test "fourteen real-shape city-only CSV contacts target Montreal without changing raw data" do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

    rows =
      for n <- 1..14,
          do: %{
            "email" => "geo-#{n}@example.org",
            "name" => "Geo #{n}",
            "city" => "Montreal",
            "signup" => "2026-09-26",
            "source" => "protest"
          }

    assert {:ok, %{contacts: contacts}} =
             ContactMigration.import_selected(rows, "protest.csv", "geo-test", admin)

    before = Enum.map(contacts, &{&1.id, &1.source_data, &1.inserted_at})

    assert {:ok, %{total: 14}} =
             CRM.directory_page(Scope.for_user(admin), %{"region" => "Montréal"})

    assert {:ok, %{total: 14}} = CRM.directory_page(Scope.for_user(admin), %{"q" => "Montréal"})

    assert {:ok, %{total: 0}} =
             CRM.directory_page(Scope.for_user(admin), %{"region" => "ROQuébec"})

    assert Enum.map(contacts, fn c ->
             p = Repo.get!(ContactMigration.Contact, c.id)
             {p.id, p.source_data, p.inserted_at}
           end) == before

    html =
      Phoenix.LiveViewTest.render_component(
        &PauseAiCaWeb.ContactSourceComponents.source_summary/1,
        id: "geo-summary",
        data: hd(contacts).source_data
      )

    assert html =~ "Montréal" and html =~ "From source city"
  end

  test "reimport preserves operator-confirmed geography and original historical dates" do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    row = %{"email" => "geo-confirmed@example.org", "city" => "Montreal"}

    assert {:ok, %{contacts: [contact]}} =
             ContactMigration.import_selected([row], "test.csv", "geo-confirmed", admin)

    data =
      Map.merge(contact.source_data, %{
        "geography" => "Montréal",
        "region_source" => "operator_confirmed",
        "historical_dates" => %{"created_at" => "2025-01-01T12:34:56Z"}
      })

    Repo.update!(Ecto.Changeset.change(contact, source_data: data))

    assert {:ok, %{contacts: [again]}} =
             ContactMigration.import_selected(
               [Map.put(row, "geography", "ROCanada")],
               "test.csv",
               "geo-confirmed",
               admin
             )

    assert again.source_data["geography"] == "Montréal"
    assert again.source_data["region_source"] == "operator_confirmed"
    assert again.source_data["historical_dates"] == data["historical_dates"]
  end
end
