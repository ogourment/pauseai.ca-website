defmodule PauseAiCaWeb.DonateLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Donations, Repo, Volunteers}
  alias PauseAiCa.Accounts.{Scope, User}
  alias PauseAiCa.Donations.Pledge

  test "bilingual form preserves errors and saves a pledge once without creating an account", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/fr/faire-un-don")
    assert has_element?(view, "#donate-page", "PauseIA Canada")
    assert has_element?(view, "#donate-page", "1819452-1")
    assert has_element?(view, "#donate-page", "791107246")

    attrs = %{
      name: "Camille Exemple",
      email: "camille@example.org",
      amount_cad: "50.25",
      notes: "Français",
      contact_consent: "false"
    }

    view |> form("#pledge-form", pledge: attrs) |> render_submit()
    assert has_element?(view, "input[value='Camille Exemple']")
    assert Repo.aggregate(Pledge, :count) == 0
    view |> form("#pledge-form", pledge: %{attrs | contact_consent: "true"}) |> render_submit()
    assert has_element?(view, "#pledge-saved", "Aucun paiement")
    pledge = Repo.one!(Pledge)
    assert pledge.locale == "fr"
    assert pledge.consented_at
    assert Decimal.equal?(pledge.amount_cad, Decimal.new("50.25"))
    assert Repo.aggregate(User, :count) == 0
    refute_receive {:email, _}
    {:ok, retry, _} = live(conn, "/en/donate")
    assert has_element?(retry, "#donate-page", "PauseAI Canada")

    retry
    |> form("#pledge-form", pledge: %{attrs | name: "Different name", contact_consent: "true"})
    |> render_submit()

    assert has_element?(retry, "#pledge-saved")
    assert Repo.aggregate(Pledge, :count) == 1
    assert Repo.one!(Pledge).name == "Camille Exemple"
  end

  test "pledges are visible only to fresh superadmin authority", %{conn: conn} do
    {:ok, _} =
      Donations.pledge(%{
        "name" => "Example",
        "email" => "pledge@example.org",
        "locale" => "en",
        "contact_consent" => true
      })

    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)
    {:ok, view, _} = live(log_in_user(conn, admin), "/admin/donation-pledges")
    assert has_element?(view, "#donation-pledges", "pledge@example.org")
    manager = user_fixture()
    {:ok, group} = Volunteers.create_group(scope, %{"name" => "Montréal"})
    {:ok, _} = Volunteers.assign_manager(scope, group.id, manager.email)
    assert {:error, :unauthorized} = Donations.list(Scope.for_user(manager))

    assert log_in_user(build_conn(), manager) |> get("/admin/donation-pledges") |> response(403) ==
             "superadmin required"

    assert {:error, {:redirect, _}} = live(build_conn(), "/admin/donation-pledges")
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Donations.list(scope)
  end

  test "suggested pledge amount updates the short form without losing contact details", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/en/donate")

    assert has_element?(view, "#funding-themes > section:nth-child(4)")
    refute has_element?(view, "#funding-themes > section:nth-child(5)")

    assert has_element?(view, "#donate-page figcaption", "Clara Lacasse")
    assert has_element?(view, "#pledge-suggestions", "not prices for a specific activity")

    view
    |> form("#pledge-form", pledge: %{name: "Alex Example", email: "alex@example.org"})
    |> render_change()

    view |> element("#pledge-suggestions button[phx-value-amount='100']") |> render_click()
    assert has_element?(view, "#pledge_amount_cad[value='100']")
    assert has_element?(view, "#pledge_name[value='Alex Example']")
    assert has_element?(view, "#pledge_email[value='alex@example.org']")

    assert has_element?(
             view,
             "#pledge-suggestions button[phx-value-amount='100'][aria-pressed='true']"
           )

    view
    |> form("#pledge-form", pledge: %{contact_consent: "true"})
    |> render_submit()

    assert has_element?(view, "#pledge-saved")
    assert Decimal.equal?(Repo.one!(Pledge).amount_cad, Decimal.new("100"))
  end
end
