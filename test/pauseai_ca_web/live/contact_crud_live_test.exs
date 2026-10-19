defmodule PauseAiCaWeb.ContactCrudLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{CRM, Repo}
  alias PauseAiCa.Accounts.{Scope, User}

  test "create, correct address, archive and restore with no account or subscription side effects",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)
    conn = log_in_user(conn, admin)
    users = Repo.aggregate(User, :count)
    subscriptions = Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count)
    {:ok, view, _} = live(conn, "/admin/contacts?locale=en&new=true")

    view
    |> form("#crm-create-form",
      contact: %{email: "quick@example.org", name: "Quick contact", city: "Toronto"}
    )
    |> render_submit()

    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#crm-contact-form input[value='Quick contact']")
    {:ok, [record]} = CRM.search(scope, "quick@example.org")

    view
    |> form("#crm-contact-form",
      contact: %{email: "corrected@example.org", name: "Corrected", city: "Montréal"}
    )
    |> render_submit()

    assert has_element?(view, "#crm-addresses", "quick@example.org")
    assert has_element?(view, "#crm-addresses", "corrected@example.org")
    view |> element("#crm-archive-contact") |> render_click()
    assert has_element?(view, "#crm-archive-contact", "Restore contact")
    assert {:ok, %{total: 0}} = CRM.directory_page(scope, %{})
    assert {:ok, %{total: 1}} = CRM.directory_page(scope, %{"archived" => "true"})

    assert {:error, :audience_changed} =
             PauseAiCa.Newsletters.Batches.contact_recipients(scope, [record.person.id])

    view |> element("#crm-archive-contact") |> render_click()
    assert {:ok, %{total: 1}} = CRM.directory_page(scope, %{})
    assert Repo.aggregate(User, :count) == users
    assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == subscriptions
    {:ok, new_view, _} = live(conn, "/admin/contacts?locale=en&new=true")

    new_view
    |> form("#crm-create-form", contact: %{email: "corrected@example.org", name: "Duplicate"})
    |> render_submit()

    assert has_element?(new_view, "#crm-error", "already assigned")
    assert {:ok, %{total: 1}} = CRM.directory_page(scope, %{})
    Repo.update!(Ecto.Changeset.change(admin, superadmin: false))

    new_view
    |> form("#crm-create-form", contact: %{email: "denied@example.org"})
    |> render_submit()

    assert Repo.get_by(PhoenixCRM.Address, email: "denied@example.org") == nil
  end
end
