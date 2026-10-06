defmodule PauseAiCaWeb.MailEntryLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Mail, Volunteers}
  alias PauseAiCa.Accounts.{User, Scope}

  test "mail landing creates an owned draft and edits survive reload without delivery", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

    member =
      user_fixture(%{email: "draft-entry@example.org"})
      |> Ecto.Changeset.change(name: "Camille", city: "Montréal")
      |> Repo.update!()

    users_before = Repo.aggregate(User, :count)
    flush_fixture_emails()
    conn = log_in_user(conn, admin)
    {:ok, index, _} = live(conn, "/manage/mail?locale=en")
    assert has_element?(index, "h1", "Emails")
    assert has_element?(index, "#mail-new-account-draft", "New personalized account drafts")
    uri = index |> element("#mail-new-account-draft") |> render_click() |> follow_redirect(conn)
    assert {:ok, chooser, _} = uri
    chooser |> form("#mail-new-search-form", %{"query" => "draft-entry"}) |> render_change()
    assert has_element?(chooser, "#mail-new", member.email)

    assert {:ok, workspace, _} =
             chooser
             |> element("button[phx-value-id='#{member.id}']")
             |> render_click()
             |> follow_redirect(conn)

    assert has_element?(workspace, "#mail-recipients", member.email)

    workspace
    |> form("#mail-template-form", %{
      "template" => %{"subject" => "Hello {{name}}", "source" => "Meeting in {{city}}"}
    })
    |> render_submit()

    assert has_element?(workspace, "#mail-drafts", "Hello Camille")
    workspace |> element("#mail-drafts a", "Edit draft") |> render_click()
    draft_uri = assert_patch(workspace)

    workspace
    |> form("#mail-draft-form", %{
      "draft" => %{"subject" => "Personal hello", "source" => "Saved personal edit"}
    })
    |> render_submit()

    {:ok, reloaded, _} = live(conn, draft_uri)
    assert has_element?(reloaded, "#mail-draft-form input[value='Personal hello']")
    assert render(reloaded) =~ "Saved personal edit"
    assert Repo.aggregate(Mail.Batch, :count) == 1
    assert Repo.aggregate(Mail.Draft, :count) == 1
    assert Repo.aggregate(User, :count) == users_before
    refute_received {:email, _}
  end

  test "the chooser honors group scope and forged, unconfirmed and revoked recipients create no batch",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(scope, %{"name" => "Montréal"})
    manager = user_fixture(%{email: "entry-manager@example.org"})
    {:ok, _} = Volunteers.assign_manager(scope, group.id, manager.email)

    member =
      user_fixture(%{email: "entry-allowed@example.org"})
      |> Ecto.Changeset.change(organizing_group_id: group.id)
      |> Repo.update!()

    outsider = user_fixture(%{email: "entry-outside@example.org"})

    unconfirmed =
      user_fixture(%{email: "entry-unconfirmed@example.org"})
      |> Ecto.Changeset.change(confirmed_at: nil, organizing_group_id: group.id)
      |> Repo.update!()

    flush_fixture_emails()
    conn = log_in_user(conn, manager)
    {:ok, chooser, _} = live(conn, "/manage/mail/new?locale=en")
    assert has_element?(chooser, "button[phx-value-id='#{member.id}']")
    refute has_element?(chooser, "button[phx-value-id='#{outsider.id}']")
    refute has_element?(chooser, "button[phx-value-id='#{unconfirmed.id}']")

    for id <- [outsider.id, unconfirmed.id, "not-a-uuid"] do
      render_click(chooser, "start-account", %{"id" => id})
      assert Repo.aggregate(Mail.Batch, :count) == 0
    end

    Repo.update!(Ecto.Changeset.change(member, organizing_group_id: nil))
    render_click(chooser, "start-account", %{"id" => member.id})
    assert Repo.aggregate(Mail.Batch, :count) == 0
    refute_received {:email, _}
  end

  test "admin writes and reloads a general email before choosing any recipient", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    conn = log_in_user(conn, admin)
    flush_fixture_emails()
    users_before = Repo.aggregate(User, :count)
    {:ok, index, _} = live(conn, "/manage/mail?locale=en")

    assert {:ok, composer, _} =
             index |> element("#mail-new-draft") |> render_click() |> follow_redirect(conn)

    assert has_element?(composer, "#newsletter-selected-count", "0 selected")

    composer
    |> form("#newsletter-draft-form",
      draft: %{subject: "Content first", source: "Saved before audience selection"}
    )
    |> render_submit()

    [draft] = Repo.all(PauseAiCa.Newsletters.Draft)
    assert draft.recipient_keys == []
    {:ok, reloaded, _} = live(conn, "/manage/mail/newsletters/#{draft.id}?locale=en")
    assert has_element?(reloaded, "input[value='Content first']")
    assert has_element?(reloaded, "#newsletter-selected-count", "0 selected")
    {:ok, landing, _} = live(conn, "/manage/mail?locale=en")
    assert has_element?(landing, "#email-drafts a", "Content first")
    assert Repo.aggregate(PauseAiCa.Newsletters.Batch, :count) == 0
    assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
    assert Repo.aggregate(User, :count) == users_before
    refute_received {:email, _}
    Repo.update!(Ecto.Changeset.change(admin, superadmin: false))
    render_click(landing, "new-email-draft", %{})
    assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == 1
  end

  defp flush_fixture_emails do
    receive do
      {:email, _} -> flush_fixture_emails()
    after
      0 -> :ok
    end
  end
end
