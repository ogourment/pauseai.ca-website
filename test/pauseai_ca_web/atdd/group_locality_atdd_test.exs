if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.GroupLocalityTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Incubators, Repo, Volunteers}

    @moduletag :atdd
    test "GROUP-LOCALITY-01 publish from Manage, open its website and keep an internal group private",
         c do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      scope = Accounts.Scope.for_user(admin)
      {:ok, group} = Volunteers.create_group(scope, %{name: "Example chapter"})
      {:ok, _} = Volunteers.create_group(scope, %{name: "National"})
      {token, _} = generate_user_magic_link_token(admin)

      c.conn
      |> visit("/users/log-in/#{token}?locale=en")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
      |> visit("/manage/groups?group=#{group.id}&tab=settings&locale=en")
      |> assert_has("[data-phx-main].phx-connected")
      |> fill_in("English name", with: "Example chapter")
      |> fill_in("French name", with: "Section exemple")
      |> check("Publish in the public directory")
      |> click_button("Save configuration")
      |> assert_has("main", text: "Only a local group can be published in the directory.")
      |> select("#profile_area_served", "Area served", option: "Local area", exact: false)
      |> click_button("Save configuration")
      |> assert_has("main", text: "Enter at least one service-area FSA before publishing.")
      |> fill_in("#profile_fsas", "Postal areas", with: "h2w 1a1", exact: false)
      |> fill_in("Office address (optional, for managers)", with: "Private test office")
      |> click_button("Save configuration")
      |> assert_has("#flash-info", text: "Group configuration saved.")
      |> visit("/manage?locale=en")
      |> click_link("main a", "Group websites")
      |> click_link("main li a", "Edit chapter homepage", exact: false)
      |> assert_has("[data-phx-main].phx-connected #chapter-form")
      |> visit("/en/groups")
      |> assert_has(".chapter-card", text: "Example chapter")
      |> refute_has(".chapter-card", text: "National")
      |> refute_has("main", text: "Private test office")

      assert {:ok, %{fsas: ["H2W"]}} = Incubators.public_group(group.id)
    end
  end
end
