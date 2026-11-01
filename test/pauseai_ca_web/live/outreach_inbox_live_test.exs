defmodule PauseAiCaWeb.OutreachInboxLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Repo}

  setup do
    admin =
      user_fixture()
      |> Ecto.Changeset.change(superadmin: true, name: "Alice Example")
      |> Repo.update!()

    previous = Application.get_env(:pauseai_ca, :outreach_mailboxes)

    mailboxes =
      for {id, name, email, locale} <- [
            {"outreach_en", "PauseAI Canada", "hello@pauseai.ca", "en"},
            {"outreach_fr", "PauseIA Canada", "bonjour@pauseia.ca", "fr"}
          ],
          do: %{
            id: id,
            name: name,
            email: email,
            locale: locale,
            owner_id: admin.id,
            enabled?: true,
            verified?: true
          }

    Application.put_env(:pauseai_ca, :outreach_mailboxes, mailboxes)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:pauseai_ca, :outreach_mailboxes),
        else: Application.put_env(:pauseai_ca, :outreach_mailboxes, previous)
    end)

    %{admin: admin, scope: Accounts.Scope.for_user(admin)}
  end

  test "outreach opens the standard editor, suggests a signature and persists only explicit edits",
       %{conn: conn, admin: admin, scope: scope} do
    conn = log_in_user(conn, admin)
    {:ok, inbox, _} = live(conn, "/manage/mail/inbox?locale=en")

    inbox
    |> form("#outreach-create-draft",
      outreach: %{
        mailbox_ref: "outreach_en",
        email: "partner@example.org",
        subject: "Partnership"
      }
    )
    |> render_submit()

    {:ok, [draft]} = PauseAiCa.Newsletters.Drafts.list(scope)
    assert_redirect(inbox, "/manage/mail/drafts/#{draft.id}?locale=en")
    assert draft.source == ""
    {:ok, editor, _} = live(conn, "/manage/mail/drafts/#{draft.id}?locale=en")
    assert has_element?(editor, "#newsletter-content")
    assert has_element?(editor, "#outreach-signature-hint", "Alice")

    assert has_element?(
             editor,
             "select[name='draft[outreach_mailbox_ref]'] option[value='outreach_fr']",
             "bonjour@pauseia.ca"
           )

    refute has_element?(editor, "#email-recipient-settings")
    editor |> element("button", "Add signature") |> render_click()
    assert has_element?(editor, "#newsletter-save-status", "Unsaved changes")
    assert Repo.get!(PauseAiCa.Newsletters.Draft, draft.id).source == ""

    editor
    |> form("#newsletter-draft-form",
      draft: %{
        source: "Hello partner.\n\nAlice",
        outreach_email: "partner@example.org",
        outreach_mailbox_ref: "outreach_fr"
      }
    )
    |> render_submit()

    {:ok, saved} = PauseAiCa.Newsletters.Drafts.get(scope, draft.id)
    assert saved.source == "Hello partner.\n\nAlice"
    assert saved.edition == "fr"
    {:ok, reloaded, _} = live(conn, "/manage/mail/drafts/#{draft.id}?locale=en")
    refute has_element?(reloaded, "button", "Add signature")
    assert Repo.aggregate(PauseAiCa.Newsletters.Batch, :count) == 0
  end

  test "conversation reads escape inbound content and another admin replies in their own draft",
       %{conn: conn, admin: admin} do
    conversation =
      Repo.insert!(%PhoenixCRM.Conversation{
        mailbox_ref: "outreach_en",
        subject: "Partner reply",
        participants: ["partner@example.org"],
        actor_id: admin.id
      })

    Repo.insert!(%PhoenixCRM.Message{
      conversation_id: conversation.id,
      mailbox_ref: "outreach_en",
      direction: :inbound,
      idempotency_key: "synthetic-inbound-#{conversation.id}",
      rfc_message_id: "<reply@example.org>",
      actor_id: admin.id,
      outcome: :received,
      envelope: %{
        "from" => "partner@example.org",
        "to" => ["hello@pauseai.ca"],
        "subject" => "Partner reply"
      },
      body_text: "<img src=x onerror=alert(1)> Please reply.",
      body_html: "<img src='https://tracking.example.org/pixel'>"
    })

    other =
      user_fixture()
      |> Ecto.Changeset.change(superadmin: true, name: "Bob Example")
      |> Repo.update!()

    conn = log_in_user(conn, other)
    {:ok, view, html} = live(conn, "/manage/mail/conversations/#{conversation.id}?locale=en")
    assert html =~ "Please reply."
    refute has_element?(view, "#outreach-messages img")
    refute html =~ "https://tracking.example.org/pixel"
    view |> element("#outreach-reply") |> render_click()
    {:ok, [draft]} = PauseAiCa.Newsletters.Drafts.list(Accounts.Scope.for_user(other))
    assert draft.owner_id == other.id
    assert draft.conversation_id == conversation.id
    assert draft.outreach_email == "partner@example.org"
    assert_redirect(view, "/manage/mail/drafts/#{draft.id}?locale=en")
    {:ok, revoked, _} = live(conn, "/manage/mail/conversations/#{conversation.id}?locale=en")
    other |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    revoked |> element("#outreach-reply") |> render_click()
    assert_redirect(revoked, "/dashboard")
    assert Repo.aggregate(PauseAiCa.Newsletters.Batch, :count) == 0
  end

  test "Inbox exposes durable processing recovery without resending uncertain notifications", %{
    conn: conn,
    admin: admin
  } do
    flush_setup_mail()

    receipt =
      Repo.insert!(%PauseAiCa.Outreach.Receipt{
        payload: %{"items" => []},
        payload_digest: :crypto.hash(:sha256, "synthetic-recovery"),
        state: "failed",
        attempts: 3,
        error: "attachment_fetch_failed"
      })

    conversation =
      Repo.insert!(%PhoenixCRM.Conversation{
        mailbox_ref: "outreach_en",
        subject: "Recovery discussion",
        participants: ["partner@example.org"],
        actor_id: admin.id
      })

    message =
      Repo.insert!(%PhoenixCRM.Message{
        conversation_id: conversation.id,
        mailbox_ref: "outreach_en",
        direction: :inbound,
        idempotency_key: "recovery-inbound",
        actor_id: "system:brevo-inbound",
        outcome: :received
      })

    notification =
      Repo.insert!(%PauseAiCa.Outreach.Notification{
        conversation_id: conversation.id,
        message_id: message.id,
        mailbox_ref: "outreach_en",
        recipient_actor_id: admin.id,
        state: "unknown"
      })

    {:ok, view, _} = live(log_in_user(conn, admin), "/manage/mail/inbox?locale=en")
    assert has_element?(view, "#outreach-processing-attention", "Processing stopped")

    assert has_element?(
             view,
             "#outreach-notification-#{notification.id}",
             "Check the provider outcome before any resend"
           )

    refute has_element?(view, "#outreach-notification-#{notification.id} button")
    view |> element("#outreach-receipt-#{receipt.id} button", "Retry") |> render_click()
    assert has_element?(view, "#outreach-receipt-#{receipt.id}", "Queued for processing")
    assert %{state: "pending", attempts: 0} = Repo.get!(PauseAiCa.Outreach.Receipt, receipt.id)
    assert Repo.get!(PauseAiCa.Outreach.Notification, notification.id).state == "unknown"
    refute_receive {:email, _}
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    view |> element("#outreach-receipt-#{receipt.id} button", "Retry") |> render_click()
    assert_redirect(view, "/dashboard")
  end

  test "ordinary confirmed users cannot read outreach inbox", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/manage/mail/inbox?locale=en")
  end

  defp flush_setup_mail do
    receive do
      {:email, _} -> flush_setup_mail()
    after
      0 -> :ok
    end
  end
end
