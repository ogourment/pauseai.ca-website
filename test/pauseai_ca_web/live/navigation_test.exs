defmodule PauseAiCaWeb.NavigationTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Volunteers.Manager
  alias PauseAiCaWeb.Navigation

  test "breadcrumb context does not invent account or administrative visits" do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

    assert Navigation.breadcrumb_context(Scope.for_user(admin), "fr") == %{
             roots: [],
             sections: []
           }

    assert Navigation.mail_breadcrumb_context(Scope.for_user(admin), "fr", true) == %{
             roots: [],
             sections: []
           }
  end

  test "superadmin gets separate Admin, Management and own account navigation", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    {:ok, view, html} = live(log_in_user(conn, admin), "/admin/contacts?locale=en")
    assert has_element?(view, "#manage-menu [data-area=manage]", "Contacts")
    assert has_element?(view, "#manage-menu [data-area=manage]", "Emails")
    assert has_element?(view, "[data-navigation-item=\"pauseai.contacts\"][aria-current=page]")
    assert has_element?(view, "#account-menu [data-area=account]", "My profile")
    refute has_element?(view, "#manage-menu [data-area=account]")
    refute has_element?(view, ".management-chrome")
    refute has_element?(view, "#management-tabs")
    {donate_position, _} = :binary.match(html, "signed-campaign-controls")
    {involvement_position, _} = :binary.match(html, "id=\"involvement-menu\"")
    assert donate_position < involvement_position
  end

  test "management CRM entries preserve capabilities and resolve closed workspace URLs" do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    items = Navigation.assemble(Scope.for_user(admin), "en")

    crm =
      Enum.filter(
        items,
        &(&1.id in [
            "pauseai.contacts",
            "pauseai.accounts",
            "pauseai.contact_lists",
            "pauseai.mail",
            "pauseai.newsletters"
          ])
      )

    assert Enum.all?(crm, &(&1.area == :manage))
    assert length(crm) == 5

    assert {:ok, "/admin/contacts?locale=fr"} =
             Navigation.resolve_route(:contacts, %{locale: "fr"})

    assert {:ok, "/manage/lists?locale=fr"} =
             Navigation.resolve_route(:contact_lists, %{locale: "fr"})

    {:ok, emails} = Navigation.resolve_route(:mail, %{locale: "fr"})

    assert URI.decode_query(URI.parse(emails).query) == %{
             "locale" => "fr",
             "workspace" => "emails"
           }

    {:ok, newsletters} = Navigation.resolve_route(:newsletters, %{locale: "en"})

    assert URI.decode_query(URI.parse(newsletters).query) == %{
             "locale" => "en",
             "workspace" => "newsletters"
           }

    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

    refute Enum.any?(
             Navigation.assemble(Scope.for_user(admin), "en"),
             &(&1.id in ["pauseai.contacts", "pauseai.contact_lists", "pauseai.newsletters"])
           )
  end

  test "group manager retains scoped routes and never receives global contact/admin links", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    manager = user_fixture()

    {:ok, group} =
      Volunteers.create_group(Scope.for_user(admin), %{"name" => "Navigation Montréal"})

    {:ok, grant} = Volunteers.assign_manager(Scope.for_user(admin), group.id, manager.email)
    {:ok, view, _} = live(log_in_user(conn, manager), "/manage/accounts?locale=en")
    assert has_element?(view, "#manage-menu [data-area=manage]", "Accounts")
    refute has_element?(view, "#admin-menu [data-area=admin]")

    assert get(log_in_user(conn, manager), "/admin/contacts?locale=en").status == 403

    Repo.delete!(Repo.get!(Manager, grant.id))
    items = Navigation.assemble(Scope.for_user(manager), "en")
    assert Enum.all?(items, &(&1.area == :account))

    assert {:error, {:redirect, _}} =
             live(log_in_user(conn, manager), "/manage/accounts?locale=en")
  end

  test "fresh revoked superadmin authority overrides stale session flags" do
    user = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    stale = Scope.for_user(user)
    user |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert Enum.all?(Navigation.assemble(stale, "en"), &(&1.area == :account))
  end

  test "ordinary account navigation exposes only self and assembly has no business writes" do
    user = user_fixture()
    before = counts()

    assert Enum.map(Navigation.assemble(Scope.for_user(user), "en"), & &1.id) == [
             "pauseai.my-dashboard",
             "pauseai.my-profile",
             "pauseai.my-groups",
             "pauseai.settings",
             "pauseai.password"
           ]

    assert Navigation.assemble(nil, "en") == []
    assert counts() == before
  end

  test "ordinary, legacy-only and delegated accounts receive only their authorized sections and tabs",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    ordinary = user_fixture()
    {:ok, ordinary_view, _} = live(log_in_user(conn, ordinary), "/en/actions")
    assert has_element?(ordinary_view, "#brand-menu")
    assert has_element?(ordinary_view, "#account-menu")
    refute has_element?(ordinary_view, "#manage-menu")
    refute has_element?(ordinary_view, "#admin-menu")
    refute has_element?(ordinary_view, "[data-navigation-item='pauseai.mail']")

    manager = user_fixture()

    {:ok, group} =
      Volunteers.create_group(Scope.for_user(admin), %{"name" => "Compact menu managers"})

    {:ok, grant} = Volunteers.assign_manager(Scope.for_user(admin), group.id, manager.email)
    {:ok, legacy_view, _} = live(log_in_user(conn, manager), "/manage/mail?locale=en")
    assert has_element?(legacy_view, "#manage-menu [data-navigation-item='pauseai.mail']")
    refute has_element?(legacy_view, "#admin-menu")
    refute has_element?(legacy_view, "[data-navigation-item='mail.conversations']")

    old = Application.get_env(:pauseai_ca, :outreach_mailboxes)

    Application.put_env(:pauseai_ca, :outreach_mailboxes, [
      %{
        id: "outreach_en",
        name: "PauseAI Canada",
        email: "hello@pauseai.ca",
        locale: "en",
        owner_id: admin.id,
        enabled?: true,
        verified?: true
      }
    ])

    on_exit(fn ->
      if old,
        do: Application.put_env(:pauseai_ca, :outreach_mailboxes, old),
        else: Application.delete_env(:pauseai_ca, :outreach_mailboxes)
    end)

    {:ok, _} =
      PauseAiCa.Outreach.grant_mailbox(Scope.for_user(admin), "outreach_en", manager.id, 0)

    {:ok, delegated_view, _} = live(log_in_user(conn, manager), "/manage/mail/inbox?locale=en")
    assert has_element?(delegated_view, "[data-navigation-item='mail.conversations']")
    refute has_element?(delegated_view, "#admin-menu")
    Repo.delete!(Repo.get!(Manager, grant.id))
    render_submit(delegated_view, "filter", %{"filters" => %{"q" => "", "mailbox_ref" => ""}})
    assert has_element?(delegated_view, "#outreach-no-access")
    refute has_element?(delegated_view, "#manage-menu")
    refute has_element?(delegated_view, "[data-navigation-item='pauseai.mail']")
    refute has_element?(delegated_view, "[data-navigation-item='mail.conversations']")
  end

  defp counts,
    do:
      Enum.map(
        [
          PauseAiCa.Accounts.User,
          PauseAiCa.ContactMigration.Contact,
          PauseAiCa.Volunteers.Manager,
          PauseAiCa.Volunteers.Invitation,
          PauseAiCa.Mail.Batch,
          PauseAiCa.Mail.Draft
        ],
        &Repo.aggregate(&1, :count)
      )
end
