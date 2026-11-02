defmodule PauseAiCaWeb.MailboxAccessLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Outreach, Repo, Volunteers}

  setup do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    manager = user_fixture(%{email: "delegated-manager@example.org"})
    stranger = user_fixture(%{email: "ordinary-account@example.org"})
    {:ok, group} = Volunteers.create_group(scope, %{"name" => "Delegated mailbox review"})
    {:ok, _} = Volunteers.assign_manager(scope, group.id, manager.email)
    previous = Application.get_env(:pauseai_ca, :outreach_mailboxes)

    boxes =
      for {id, email, locale} <- [
            {"outreach_en", "hello@pauseai.ca", "en"},
            {"outreach_fr", "bonjour@pauseia.ca", "fr"}
          ],
          do: %{
            id: id,
            name: "PauseAI Canada",
            email: email,
            locale: locale,
            owner_id: admin.id,
            enabled?: true,
            verified?: true
          }

    Application.put_env(:pauseai_ca, :outreach_mailboxes, boxes)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pauseai_ca, :outreach_mailboxes, previous),
        else: Application.delete_env(:pauseai_ca, :outreach_mailboxes)
    end)

    %{admin: admin, scope: scope, manager: manager, stranger: stranger}
  end

  test "superadmin grants one selected existing manager one mailbox, then revokes without granting a role",
       c do
    conn = log_in_user(c.conn, c.admin)
    {:ok, view, _} = live(conn, "/manage/mail/access?locale=en")
    assert has_element?(view, "#mailbox-manager-picker option[value='#{c.manager.id}']")
    refute has_element?(view, "#mailbox-manager-picker option[value='#{c.stranger.id}']")
    view |> form("#mailbox-manager-picker", access: %{user_id: c.manager.id}) |> render_change()

    view
    |> element("#mailbox-cell-outreach_en-#{c.manager.id} button", "Grant access")
    |> render_click()

    assert has_element?(view, "#mailbox-cell-outreach_en-#{c.manager.id} button", "Revoke")
    assert has_element?(view, "#mailbox-cell-outreach_fr-#{c.manager.id} button", "Grant access")
    assert {:ok, [box]} = Outreach.mailboxes(Accounts.Scope.for_user(c.manager))
    assert box.id == "outreach_en"

    view
    |> element("#mailbox-cell-outreach_en-#{c.manager.id} button", "Revoke")
    |> render_click()

    assert {:ok, []} = Outreach.mailboxes(Accounts.Scope.for_user(c.manager))
    assert Volunteers.allowed?(Accounts.Scope.for_user(c.manager))
    refute Repo.get!(Accounts.User, c.manager.id).superadmin
    refute has_element?(view, "#flash-info")
  end

  test "stale changes remain visible and manager cannot open or forge delegation controls", c do
    conn = log_in_user(c.conn, c.admin)
    {:ok, view, _} = live(conn, "/manage/mail/access?locale=en")
    view |> form("#mailbox-manager-picker", access: %{user_id: c.manager.id}) |> render_change()
    assert {:ok, _} = Outreach.grant_mailbox(c.scope, "outreach_en", c.manager.id, 0)

    render_click(view, "grant", %{
      "mailbox_ref" => "outreach_en",
      "user_id" => c.manager.id,
      "revision" => "0"
    })

    assert has_element?(view, "#mailbox-access-error", "Access changed")
    assert has_element?(view, "#mailbox-cell-outreach_en-#{c.manager.id} button", "Revoke")
    c.admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

    render_click(view, "revoke", %{
      "mailbox_ref" => "outreach_en",
      "user_id" => c.manager.id,
      "revision" => "1"
    })

    assert_redirect(view, "/dashboard")
    assert {:ok, [_]} = Outreach.mailboxes(Accounts.Scope.for_user(c.manager))
    assert get(log_in_user(c.conn, c.manager), "/manage/mail/access?locale=en").status == 403
  end

  test "manager without a grant sees an access explanation rather than a false empty inbox", c do
    {:ok, view, _} = live(log_in_user(c.conn, c.manager), "/manage/mail/inbox?locale=en")
    assert has_element?(view, "#outreach-no-access", "Mailbox access required")
    refute has_element?(view, "#outreach-create-draft")
    refute has_element?(view, "#outreach-filters")
    refute has_element?(view, "[data-navigation-item='mail.access']")
    render_click(view, "reply", %{})
    assert has_element?(view, "#outreach-no-access")
    assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == 0
  end

  test "granted manager sees only their mailbox and standard editor with Manage roots", c do
    assert {:ok, _} = Outreach.grant_mailbox(c.scope, "outreach_fr", c.manager.id, 0)
    manager_scope = Accounts.Scope.for_user(c.manager)
    conn = log_in_user(c.conn, c.manager)

    {:ok, private_draft} =
      Outreach.create_draft(c.scope, %{
        "mailbox_ref" => "outreach_fr",
        "email" => "private-draft@example.org",
        "subject" => "Another account's private draft"
      })

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             live(conn, "/manage/mail/drafts/#{private_draft.id}?locale=fr")

    {:ok, inbox, _} = live(conn, "/manage/mail/inbox?locale=fr")
    refute has_element?(inbox, "#outreach-no-access")
    assert has_element?(inbox, "select[name='outreach[mailbox_ref]'] option[value=outreach_fr]")
    refute has_element?(inbox, "select[name='outreach[mailbox_ref]'] option[value=outreach_en]")
    refute has_element?(inbox, "#outreach-processing-attention")
    refute has_element?(inbox, "[data-navigation-item='mail.lists']")
    {:ok, stale_filter, _} = live(conn, "/manage/mail/inbox?locale=fr&mailbox_ref=outreach_en")
    assert has_element?(stale_filter, "#outreach-no-access")
    refute has_element?(stale_filter, "#outreach-conversations")

    inbox
    |> form("#outreach-create-draft",
      outreach: %{
        mailbox_ref: "outreach_fr",
        email: "synthetic-partner@example.org",
        subject: "Delegated draft"
      }
    )
    |> render_submit()

    {:ok, [draft]} = PauseAiCa.Newsletters.Drafts.list(manager_scope)
    assert_redirect(inbox, "/manage/mail/drafts/#{draft.id}?locale=fr")
    {:ok, editor, _} = live(conn, "/manage/mail/drafts/#{draft.id}?locale=fr")
    assert has_element?(editor, "#newsletter-draft-form")
    assert has_element?(editor, "#outreach-addressing option[value=outreach_fr]")
    refute has_element?(editor, "#outreach-addressing option[value=outreach_en]")
    refute has_element?(editor, "#newsletter-delivery-limits")
    context = element(editor, "#journey-breadcrumbs") |> render()
    refute context =~ "Mon compte"
    refute context =~ "Administration"
    refute context =~ "Gestion"

    editor
    |> form("#newsletter-draft-form", draft: %{source: "Synthetic delegated content"})
    |> render_submit()

    assert Repo.get!(PauseAiCa.Newsletters.Draft, draft.id).source ==
             "Synthetic delegated content"

    assert {:ok, _} = Outreach.revoke_mailbox(c.scope, "outreach_fr", c.manager.id, 1)

    editor
    |> form("#newsletter-draft-form", draft: %{source: "Revoked attempt"})
    |> render_submit()

    assert_redirect(editor, "/dashboard")

    assert Repo.get!(PauseAiCa.Newsletters.Draft, draft.id).source ==
             "Synthetic delegated content"
  end
end
