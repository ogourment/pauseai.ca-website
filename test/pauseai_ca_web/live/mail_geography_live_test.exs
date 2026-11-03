defmodule PauseAiCaWeb.MailGeographyLiveTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, CRM, Newsletters, Repo}

  test "manual picker reuses geographic boundaries, replaces broad region and retains explicit choices",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)

    records =
      for {city, key} <- [
            {"Toronto", "toronto"},
            {"Mississauga", "gta"},
            {"Burnaby", "bc"},
            {nil, "unknown"}
          ],
          into: %{} do
        {:ok, record} = CRM.create(scope, %{name: key, email: key <> "@example.org", city: city})
        {key, record.person.id}
      end

    source =
      Repo.insert!(%PauseAiCa.ContactMigration.Contact{
        email: "bc@example.org",
        name: "bc",
        city: "Burnaby",
        source: "synthetic",
        source_data: %{
          "city" => "Burnaby",
          "sheet" => "Rest of Canada",
          "source_observation" => %{"user" => %{"timezone" => "America/Toronto"}}
        }
      })

    Repo.insert!(%PauseAiCa.CRM.ContactLink{contact_id: source.id, person_id: records["bc"]})
    {:ok, draft} = Newsletters.Drafts.create(scope)
    {:ok, view, _} = live(log_in_user(conn, admin), "/manage/mail/drafts/#{draft.id}?locale=en")

    view
    |> form("#newsletter-draft-form", draft: %{recipient_mode: "contacts"})
    |> render_change()

    view
    |> form("#newsletter-draft-form",
      draft: %{region: "ROCanada", recipient_keys: [records["bc"]]}
    )
    |> render_change()

    view |> form("#newsletter-draft-form", draft: %{candidate_q: "Toronto"}) |> render_change()
    assert has_element?(view, "#newsletter-recipient-#{records["bc"]}")

    view
    |> form("#newsletter-draft-form",
      draft: %{candidate_q: "", geography: %{areas: ["toronto_gta"]}}
    )
    |> render_change()

    assert has_element?(view, "#newsletter-recipient-#{records["toronto"]}")
    assert has_element?(view, "#newsletter-recipient-#{records["gta"]}")
    refute has_element?(view, "#newsletter-recipient-#{records["bc"]}")
    assert has_element?(view, "#draft_region option[value=''][selected]")
    assert has_element?(view, "#newsletter-picker-selected-count", "1 selected")
    assert has_element?(view, "#newsletter-selection-help", "keeps recipients")
    assert has_element?(view, "#newsletter-filter-count", "2 contacts")
    view |> element("button[phx-click=select-visible]") |> render_click()
    assert has_element?(view, "#newsletter-picker-selected-count", "3 selected")

    view
    |> form("#newsletter-draft-form", draft: %{subject: "Review", source: "Local update"})
    |> render_submit()

    {:ok, saved} = Newsletters.Drafts.get(scope, draft.id)

    assert Enum.sort(saved.recipient_keys) ==
             Enum.sort(Map.take(records, ["bc", "toronto", "gta"]) |> Map.values())

    assert saved.region == ""
    assert Repo.aggregate(Newsletters.Subscription, :count) == 0
    assert Repo.aggregate(Newsletters.Batch, :count) == 0

    {:ok, reloaded, _} =
      live(log_in_user(build_conn(), admin), "/manage/mail/drafts/#{draft.id}?locale=en")

    assert has_element?(reloaded, "#newsletter-picker-selected-count", "3 selected")
    assert has_element?(reloaded, "#mail-geography-areas")
  end

  test "province city FSA and unknown inputs use shared normalization without saved lists", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)

    {:ok, _} =
      CRM.observe(
        scope,
        %{email: "postal@example.org", name: "Postal", fsa: "M5V"},
        "synthetic",
        "postal"
      )

    {:ok, city} = CRM.create(scope, %{email: "city@example.org", name: "City", city: "Vancouver"})
    {:ok, unknown} = CRM.create(scope, %{email: "unknown@example.org", name: "Unknown"})
    {:ok, draft} = Newsletters.Drafts.create(scope)
    {:ok, view, _} = live(log_in_user(conn, admin), "/manage/mail/drafts/#{draft.id}?locale=en")

    view
    |> form("#newsletter-draft-form",
      draft: %{recipient_mode: "contacts"}
    )
    |> render_change()

    view
    |> form("#newsletter-draft-form", draft: %{geography: %{provinces: ["BC"]}})
    |> render_change()

    assert has_element?(view, "#newsletter-recipient-#{city.person.id}")
    assert has_element?(view, "#newsletter-filter-count", "1 contacts")

    view
    |> form("#newsletter-draft-form", draft: %{geography: %{provinces: [""], fsas: "m5v"}})
    |> render_change()

    refute has_element?(view, "#newsletter-recipient-#{city.person.id}")
    assert has_element?(view, "#newsletter-filter-count", "1 contacts")

    view
    |> form("#newsletter-draft-form", draft: %{geography: %{fsas: "", unknown: "true"}})
    |> render_change()

    assert has_element?(view, "#newsletter-recipient-#{unknown.person.id}")
    refute has_element?(view, "#newsletter-recipient-#{city.person.id}")
    assert Repo.aggregate(PhoenixCRM.MailingList, :count) == 0
  end

  test "UI-authored geography rules filter manual contacts without subscriber membership and fail closed on archive",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)

    {:ok, city} =
      CRM.create(scope, %{email: "custom-city@example.org", name: "Custom city", city: "Kingston"})

    {:ok, _postal} =
      CRM.observe(
        scope,
        %{email: "custom-postal@example.org", name: "Custom postal", fsa: "K1A"},
        "synthetic",
        "custom-postal"
      )

    {:ok, other} =
      CRM.create(scope, %{email: "other@example.org", name: "Other", city: "Vancouver"})

    {:ok, list} =
      Newsletters.Lists.save(scope, nil, %{
        "name" => "Custom Ontario area",
        "city" => "Kingston",
        "fsas" => "K1A"
      })

    {:ok, draft} = Newsletters.Drafts.create(scope)
    {:ok, view, _} = live(log_in_user(conn, admin), "/manage/mail/drafts/#{draft.id}?locale=en")

    view
    |> form("#newsletter-draft-form", draft: %{recipient_mode: "contacts"})
    |> render_change()

    view |> form("#newsletter-draft-form", draft: %{saved_filter_id: list.id}) |> render_change()
    assert has_element?(view, "#mail-saved-geography option[value='#{list.id}'][selected]")
    assert has_element?(view, "#newsletter-recipient-#{city.person.id}")
    refute has_element?(view, "#newsletter-recipient-#{other.person.id}")
    assert has_element?(view, "#newsletter-filter-count", "2 contacts")
    assert has_element?(view, "#draft_recipient_mode option[value=contacts][selected]")
    assert Repo.aggregate(Newsletters.Subscription, :count) == 0
    {:ok, _} = Newsletters.Lists.archive(scope, list)
    view |> form("#newsletter-draft-form", draft: %{candidate_q: "Custom"}) |> render_change()
    assert has_element?(view, "#newsletter-draft-error", "unavailable")
    refute has_element?(view, "#newsletter-recipient-#{city.person.id}")
    assert Repo.aggregate(Newsletters.Batch, :count) == 0
  end
end
