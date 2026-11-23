defmodule PauseAiCaWeb.ProfileLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias PauseAiCa.{Accounts, Repo, Volunteers.Profile}

  setup :register_and_log_in_user

  test "requires an authenticated user" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/en/profile")
  end

  test "phone is optional and can be saved or cleared without a full postal code", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, "/en/profile")
    view |> form("#profile-form", profile: %{phone: "+1 613 555 0102"}) |> render_submit()
    assert Accounts.get_user!(user.id).phone == "+1 613 555 0102"
    assert is_nil(Accounts.get_user!(user.id).postal_code)
    view |> form("#profile-form", profile: %{phone: ""}) |> render_submit()
    assert is_nil(Accounts.get_user!(user.id).phone)
  end

  test "stores a full postal code and shows the matched MP honestly", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/en/profile")

    view
    |> form("#profile-form",
      profile: %{
        name: " Olivier Gourment ",
        postal_code: "h2x 1y4",
        city: " Montréal ",
        local_updates: true
      }
    )
    |> render_submit()

    refute has_element?(view, "#mp-result")
    assert is_nil(Accounts.get_user!(user.id).representative)

    view
    |> form("#mp-form", lookup: %{postal_code: "h2x 1y4"})
    |> render_submit()

    render_async(view)
    assert has_element?(view, "#mp-result", "Steven Guilbeault")
    assert has_element?(view, "#mp-result", "Laurier—Sainte-Marie")
    assert has_element?(view, "#mp-position", "not yet documented")

    stored = Repo.get!(Accounts.User, user.id)
    assert stored.name == "Olivier Gourment"
    assert stored.postal_code == "H2X1Y4"
    assert stored.city == "Montréal"
    assert stored.fsa == "H2X"
    assert stored.local_updates
    assert stored.representative["name"] == "Steven Guilbeault"

    view |> form("#profile-form", profile: %{postal_code: "K1A"}) |> render_submit()
    assert %{fsa: "K1A", postal_code: nil, representative: nil} = Accounts.get_user!(user.id)
    refute has_element?(view, "#mp-result")

    view |> form("#profile-form", profile: %{postal_code: ""}) |> render_submit()
    assert %{fsa: nil, postal_code: nil} = Accounts.get_user!(user.id)
  end

  test "keeps conflicting city and legacy contacts visible until edited, then respects clearing",
       %{
         conn: conn,
         user: user
       } do
    user |> Ecto.Changeset.change(city: "Montréal") |> Repo.update!()

    legacy =
      Repo.insert!(%Profile{
        user_id: user.id,
        draft: %{"city" => "Québec", "discord_handle" => "draft-handle"},
        details: %{"country" => "Canada", "contact_notes" => "Legacy instructions"}
      })

    {:ok, view, _} = live(conn, "/en/profile")
    assert has_element?(view, "#profile-city-conflict", "Québec")
    assert has_element?(view, "#profile_city[value='Montréal']")
    assert has_element?(view, "#profile_country[value='Canada']")
    assert has_element?(view, "#profile_discord_handle[value='draft-handle']")

    view |> form("#profile-form", profile: %{name: "Test Supporter"}) |> render_submit()
    assert has_element?(view, "#profile-city-conflict")

    view
    |> form("#profile-form", profile: %{city: "", discord_handle: "", contact_notes: ""})
    |> render_submit()

    reopened_user = Accounts.get_user!(user.id)
    assert reopened_user.city == nil
    assert reopened_user.profile_contact["discord_handle"] == nil
    assert reopened_user.profile_contact["contact_notes"] == nil
    assert Repo.get!(Profile, legacy.id).draft == legacy.draft
    assert Repo.get!(Profile, legacy.id).details == legacy.details

    {:ok, reopened, _} = live(conn, "/en/profile")
    refute has_element?(reopened, "#profile-city-conflict")
    refute has_element?(reopened, "#profile_city[value='Québec']")
    refute has_element?(reopened, "#profile_discord_handle[value='draft-handle']")
  end

  test "requires the newly selected handle and preserves all submitted values on error", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, "/en/profile")

    view
    |> form("#profile-form", profile: %{city: "Sudbury", contact_preference: "signal"})
    |> render_submit()

    assert has_element?(view, "#profile-form details[open]", "can't be blank")
    assert has_element?(view, "#profile_city[value='Sudbury']")
    assert is_nil(Accounts.get_user!(user.id).city)

    view |> form("#profile-form", profile: %{signal_number: "+1 705 555 0102"}) |> render_submit()

    stored = Accounts.get_user!(user.id)
    assert stored.city == "Sudbury"
    assert stored.profile_contact["contact_preference"] == "signal"
    assert stored.profile_contact["signal_number"] == "+1 705 555 0102"
    assert has_element?(view, "#profile-save-status", "Profile saved.")
  end

  test "looks up an unsaved postal code without changing profile details", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _} = live(conn, "/en/profile")

    view |> form("#mp-form", lookup: %{postal_code: "H2X"}) |> render_submit()
    assert has_element?(view, "#mp-lookup-error", "Enter a complete Canadian postal code.")

    view |> form("#mp-form", lookup: %{postal_code: "H2X 1Y4"}) |> render_submit()
    render_async(view)
    assert has_element?(view, "#mp-result", "Steven Guilbeault")
    assert %{postal_code: nil, fsa: nil, representative: nil} = Accounts.get_user!(user.id)

    {:ok, reopened, _} = live(conn, "/en/profile")
    refute has_element?(reopened, "#mp-result")
  end

  test "saving in one tab preserves untargeted changes from another tab", %{
    conn: conn,
    user: user
  } do
    {:ok, location_view, _} = live(conn, "/en/profile")
    {:ok, phone_view, _} = live(conn, "/en/profile")

    location_view
    |> form("#profile-form", profile: %{city: "Sudbury", postal_code: "P3E"})
    |> render_submit()

    phone_view
    |> form("#profile-form", profile: %{phone: "+1 705 555 0102"})
    |> render_submit()

    assert %{city: "Sudbury", fsa: "P3E", phone: "+1 705 555 0102"} =
             Accounts.get_user!(user.id)
  end

  test "manages saved nuggets and personal resource links", %{conn: conn, user: user} do
    {:ok, user} = Accounts.save_resource(user, "risk")
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/en/profile")

    assert has_element?(view, "#profile-saved-resources", "Understand existential risk")

    view
    |> form("#custom-resource-form", resource: %{url: "https://example.org/useful-reading"})
    |> render_submit()

    assert has_element?(view, "#custom-resources a[href='https://example.org/useful-reading']")

    stored = Repo.get!(Accounts.User, user.id)
    assert stored.custom_resource_urls == ["https://example.org/useful-reading"]

    view
    |> element("button[phx-click='remove-saved-resource'][phx-value-resource='risk']")
    |> render_click()

    refute has_element?(view, "#profile-saved-resources", "Understand existential risk")
  end
end
