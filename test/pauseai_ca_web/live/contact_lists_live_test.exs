defmodule PauseAiCaWeb.ContactListsLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, ContactLists, CRM, Repo}

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{conn: log_in_user(conn, admin), scope: Accounts.Scope.for_user(admin), admin: admin}
  end

  test "static list creation, selected archive and restore use the same collection", c do
    {:ok, view, _} = live(c.conn, "/manage/lists?locale=en")

    view
    |> form("#contact-list-form", %{"list" => %{"name" => "Campaign helpers", "kind" => "static"}})
    |> render_submit()

    path = assert_patch(view)
    {:ok, [list]} = ContactLists.list(c.scope)
    assert path =~ list.id
    assert has_element?(view, "#selected-contact-list", "Campaign helpers")
    assert has_element?(view, "#contact-list-compose-newsletter")
    view |> element("#contact-list-collection-select-#{list.id}") |> render_click()
    view |> element("button[phx-click='archive-selected']") |> render_click()
    assert_patch(view)
    assert {:ok, []} = ContactLists.list(c.scope)
    {:ok, archived, _} = live(c.conn, "/manage/lists?locale=en&archived=true")
    archived |> element("#contact-list-collection-select-#{list.id}") |> render_click()
    archived |> element("button[phx-click='restore-selected']") |> render_click()
    assert_patch(archived)
    assert {:ok, [%{id: id}]} = ContactLists.list(c.scope)
    assert id == list.id
    refute_received {:email, %{subject: "Campaign helpers"}}
  end

  test "Vancouver city rules expose complete contacts and open the common newsletter editor", c do
    {:ok, _} =
      CRM.create(c.scope, %{
        name: "Vancouver volunteer",
        email: "vancouver-list@example.org",
        city: "Vancouver"
      })

    {:ok, _} =
      CRM.create(c.scope, %{
        name: "Burnaby volunteer",
        email: "burnaby-list@example.org",
        city: "Burnaby"
      })

    {:ok, view, _} = live(c.conn, "/manage/lists?locale=en")

    view
    |> form("#contact-list-form", %{
      "list" => %{
        "name" => "Vancouver",
        "kind" => "dynamic",
        "city" => "Vancouver",
        "region" => "",
        "fsas" => ""
      }
    })
    |> render_submit()

    assert_patch(view)
    assert has_element?(view, "#selected-contact-list", "1 matching contacts")
    {:ok, [list]} = ContactLists.list(c.scope)
    assert has_element?(view, "a[href*='saved_filter_id=#{list.id}']", "View contacts")
    view |> element("#contact-list-compose-newsletter") |> render_click()
    {path, _flash} = assert_redirect(view)
    assert path =~ "/manage/mail/drafts/"
    [draft] = Repo.all(PauseAiCa.Newsletters.Draft)
    assert draft.recipient_mode == "list"
    assert draft.mailing_list_id == list.id
    assert Repo.aggregate(PauseAiCa.Newsletters.Batch, :count) == 0
  end

  test "revoked permission prevents a retained list form from writing", c do
    {:ok, view, _} = live(c.conn, "/manage/lists?locale=en")
    c.admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

    view
    |> form("#contact-list-form", %{"list" => %{"name" => "Revoked list", "kind" => "static"}})
    |> render_submit()

    assert_redirect(view, "/dashboard")
    assert Repo.aggregate(PhoenixCRM.MailingList, :count) == 0
  end
end
