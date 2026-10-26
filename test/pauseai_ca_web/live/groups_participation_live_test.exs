defmodule PauseAiCaWeb.GroupsParticipationLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Incubators, Newsletters, Participation, Repo, Volunteers}

  for {locale, path, explanation, help} <- [
        {"en", "/en/groups", "First three characters", "Help start an incubator"},
        {"fr", "/fr/groupes", "Trois premiers caractères", "Aider à créer un incubateur"}
      ] do
    test "#{locale} directory offers the shared local form even without published groups", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, unquote(path))
      assert has_element?(view, "#group-participation #participation-form")
      assert has_element?(view, "input[name='participation[name]']")
      assert has_element?(view, "input[name='participation[email]']")

      assert has_element?(
               view,
               "input[name='participation[location]'][aria-describedby='participation-fsa-help']"
             )

      assert has_element?(view, "#participation-fsa-help", unquote(explanation))
      assert has_element?(view, "#participation-motivations button", unquote(help))
      assert has_element?(view, "#participation-group-cities option[value='Toronto']")
      assert has_element?(view, "#participation-group-cities option[value='Montréal']")
      assert has_element?(view, "input[name='participation[local]'][type='checkbox'][checked]")

      assert has_element?(
               view,
               "input[name='participation[account]'][type='checkbox']:not([checked])"
             )

      assert has_element?(
               view,
               "input[name='participation[newsletter]'][type='checkbox']:not([checked])"
             )
    end
  end

  test "selecting a published group's waitlist retains personal details and explicit companion choices",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(scope, %{name: "Synthetic local group"})

    {:ok, _} =
      Incubators.configure(scope, group.id, %{
        "name_en" => "Synthetic local group",
        "name_fr" => "Groupe local synthétique",
        "published" => true
      })

    {:ok, view, _} = live(conn, "/en/groups")

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan",
        email: "groupwait@example.org",
        location: "H2X",
        city: "Ottawa",
        account: "true",
        newsletter: "true"
      }
    )
    |> render_change()

    view |> element("#group-#{group.id} button", "Join the waitlist") |> render_click()
    assert has_element?(view, "input[name='participation[name]'][value='Morgan']")
    assert has_element?(view, "input[name='participation[email]'][value='groupwait@example.org']")
    assert has_element?(view, "input[name='participation[location]'][value='H2X']")
    assert has_element?(view, "input[name='participation[city]'][value='Ottawa']")
    assert has_element?(view, "input[name='participation[account]'][type='checkbox'][checked]")
    assert has_element?(view, "input[name='participation[newsletter]'][type='checkbox'][checked]")

    assert has_element?(
             view,
             "#participation-selected-group",
             "Waitlist for Synthetic local group"
           )

    assert has_element?(view, "a[href='/groups/#{group.id}/join?locale=en']")
    view |> form("#participation-form") |> render_submit()
    assert Repo.one!(Participation.Request).context["incubator_group_id"] == group.id
  end

  test "helping a new incubator uses existing email confirmation without creating membership or an account",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/en/groups")

    view
    |> element("#participation-motivations button", "Help start an incubator")
    |> render_click()

    # An in-flight form change can contain the preceding hidden kind.
    # The explicit server-side mode remains authoritative.
    view
    |> form("#participation-form")
    |> render_change(%{"participation" => %{"local_kind" => "waitlist"}})

    assert has_element?(view, "input[name='participation[local_kind]'][value='help']")
    assert has_element?(view, "textarea[name='participation[help_text]']")

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan",
        email: "newgroup@example.org",
        location: "M5V",
        city: "Toronto",
        help_text: "I can help find a meeting venue."
      }
    )
    |> render_submit()

    assert has_element?(view, "#account-email-pending")
    assert_receive {:email, mail}
    assert mail.subject == "Confirm your choices"

    assert %{state: "pending", local_kind: "help", account: false, newsletter: false} =
             Repo.one!(Participation.Request)

    [url] = Regex.run(~r{https?://[^\s]+/participation/confirm\?[^\s]+}, mail.text_body)
    token = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("token")

    assert {:ok, %{state: "confirmed", local_kind: "help", city: "Toronto"}} =
             Participation.confirm(token)

    assert Repo.aggregate(Incubators.Membership, :count) == 0
    assert Repo.aggregate(Volunteers.Manager, :count) == 0
    assert Accounts.get_user_by_email("newgroup@example.org") == nil
    assert Repo.aggregate(Newsletters.Subscription, :count) == 0
  end

  test "an existing account keeps its profile fields and email through local-mode changes", %{
    conn: conn
  } do
    user = user_fixture() |> Ecto.Changeset.change(name: "Camille", fsa: "H2X") |> Repo.update!()
    {:ok, view, _} = live(log_in_user(conn, user), "/en/groups")

    assert has_element?(
             view,
             "input[name='participation[email]'][readonly][value='#{user.email}']"
           )

    view
    |> element("#participation-motivations button", "Help start an incubator")
    |> render_click()

    assert has_element?(view, "input[name='participation[name]'][value='Camille']")
    assert has_element?(view, "input[name='participation[location]'][value='H2X']")
    view |> element("#participation-motivations button", "Join the waitlist") |> render_click()
    assert has_element?(view, "input[name='participation[email]'][value='#{user.email}']")
    assert Accounts.get_user!(user.id).name == "Camille"
    assert Accounts.get_user!(user.id).fsa == "H2X"
  end
end
