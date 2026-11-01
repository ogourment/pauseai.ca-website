defmodule PauseAiCa.OutreachTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Outreach, Newsletters}
  alias PauseAiCa.Newsletters.{Batches, Drafts, Delivery}
  alias PauseAiCa.Outreach.{Receipt, Notification}

  setup do
    owner = user_fixture() |> change(superadmin: true, name: "Synthetic Owner") |> Repo.update!()

    sender =
      user_fixture() |> change(superadmin: true, name: "Synthetic Sender") |> Repo.update!()

    # Authentication fixtures legitimately emit setup mail; consume only those
    # known deliveries before asserting the outreach operation's own effects.
    for user <- [owner, sender] do
      address = user.email
      assert_receive {:email, %{to: [{_, ^address}]}}
    end

    boxes = [
      %{
        id: "outreach_en",
        name: "PauseAI Canada",
        email: "hello@pauseai.ca",
        locale: "en",
        owner_id: owner.id,
        enabled?: true,
        verified?: true,
        receiving_addresses: ["hello@reply.pauseai.ca"]
      },
      %{
        id: "outreach_fr",
        name: "PauseIA Canada",
        email: "bonjour@pauseia.ca",
        locale: "fr",
        owner_id: owner.id,
        enabled?: true,
        verified?: true,
        receiving_addresses: ["bonjour@reply.pauseia.ca"]
      }
    ]

    previous = Application.get_env(:pauseai_ca, :outreach_mailboxes)
    env = Application.fetch_env!(:pauseai_ca, :mail_environment)
    Application.put_env(:pauseai_ca, :outreach_mailboxes, boxes)
    Application.put_env(:pauseai_ca, :mail_environment, :test)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pauseai_ca, :outreach_mailboxes, previous),
        else: Application.delete_env(:pauseai_ca, :outreach_mailboxes)

      Application.put_env(:pauseai_ca, :mail_environment, env)
    end)

    %{owner: owner, sender: sender, scope: Accounts.Scope.for_user(sender), boxes: boxes}
  end

  defp draft(scope, attrs \\ %{}) do
    Outreach.create_draft(
      scope,
      Map.merge(
        %{
          "mailbox_ref" => "outreach_en",
          "email" => "partner@example.org",
          "subject" => "Synthetic partnership",
          "source" => "A synthetic collaboration proposal.\n\nSynthetic"
        },
        attrs
      )
    )
  end

  defp incoming(message_id, attrs \\ %{}) do
    %{
      "items" => [
        Map.merge(
          %{
            "Uuid" => ["1a825d56-029b-4a41-b8e4-61670463431b"],
            "MessageId" => "<reply@partner.example.org>",
            "InReplyTo" => message_id,
            "From" => %{"Name" => "Synthetic partner", "Address" => "partner@example.org"},
            "Recipients" => ["hello@reply.pauseai.ca"],
            "To" => [%{"Address" => "hello@pauseai.ca"}],
            "Cc" => [],
            "Subject" => "Re: Synthetic partnership",
            "SentAtDate" => "Tue, 1 Sep 2020 09:53:21 +0200",
            "RawTextBody" => "A synthetic reply",
            "RawHtmlBody" => "<script>untrusted()</script>",
            "Attachments" => [],
            "Headers" => %{"References" => [message_id]}
          },
          attrs
        )
      ]
    }
  end

  test "save configured disabled drafts without account/consent creation; prepare requires activation and fresh authority",
       c do
    Application.put_env(
      :pauseai_ca,
      :outreach_mailboxes,
      Enum.map(c.boxes, &%{&1 | enabled?: false})
    )

    users = Repo.aggregate(Accounts.User, :count)
    subscriptions = Repo.aggregate(Newsletters.Subscription, :count)
    assert {:ok, draft} = draft(c.scope)
    assert draft.recipient_mode == "outreach"
    assert Repo.get_by(PhoenixCRM.Address, email: "partner@example.org")
    assert Repo.aggregate(Accounts.User, :count) == users
    assert Repo.aggregate(Newsletters.Subscription, :count) == subscriptions
    assert {:error, :mailbox_unavailable} = Batches.prepare(c.scope, draft, "outreach", [], true)
    c.sender |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Outreach.list(c.scope)
    assert {:error, :unauthorized} = Drafts.save(c.scope, draft, %{"subject" => "Denied"})
  end

  test "existing reviewed dispatch archives exactly once with actual sender and no generic authentication archive",
       c do
    {:ok, draft} = draft(c.scope)
    assert {:error, :review_required} = Batches.prepare(c.scope, draft, "outreach", [], false)
    {:ok, batch} = Batches.prepare(c.scope, draft, "outreach", [], true)
    assert batch.sender_email == "hello@pauseai.ca"
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 0
    assert {:ok, _} = Batches.approve(c.scope, batch.id)
    assert {:ok, :completed} = Batches.dispatch(c.scope, batch.id)
    assert_receive {:email, email}
    assert email.from == {"PauseAI Canada", "hello@pauseai.ca"}
    assert email.text_body =~ "Unsubscribe"
    [message] = Repo.all(PhoenixCRM.Message)
    [delivery] = Repo.all(Delivery)
    assert message.actor_id == c.sender.id
    assert message.delivery_ref == delivery.id
    assert message.outcome == :accepted
    assert message.body_text == email.text_body
    assert email.headers["Message-ID"] == message.rfc_message_id
    assert {:ok, :not_approved} = Batches.dispatch(c.scope, batch.id)
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 1

    assert {:ok, _} =
             PauseAiCa.Mailer.deliver(
               Swoosh.Email.new()
               |> Swoosh.Email.to(c.sender.email)
               |> Swoosh.Email.from("info@pauseai.ca")
               |> Swoosh.Email.subject("Auth synthetic")
               |> Swoosh.Email.text_body("Never archive this"),
               admin_actor_id: c.sender.id
             )

    assert Repo.aggregate(PhoenixCRM.Message, :count) == 1
  end

  test "durable webhook replay threads exactly and notifies last submitting admin once", c do
    {:ok, draft} = draft(c.scope)
    {:ok, batch} = Batches.prepare(c.scope, draft, "outreach", [], true)
    {:ok, _} = Batches.approve(c.scope, batch.id)
    {:ok, :completed} = Batches.dispatch(c.scope, batch.id)
    [outbound] = Repo.all(PhoenixCRM.Message)
    payload = incoming(outbound.rfc_message_id)
    assert {:ok, receipt} = Outreach.receive(payload)
    assert receipt.state == "pending"
    assert {:ok, replay_receipt} = Outreach.receive(payload)
    assert replay_receipt.id == receipt.id
    assert {:ok, %{messages: [reply]}} = Outreach.process_receipt(receipt.id)
    assert reply.conversation_id == draft.conversation_id
    assert reply.source["receipt_id"] == receipt.id
    assert reply.source["item_index"] == 0
    assert {:ok, %{messages: []}} = Outreach.process_receipt(receipt.id)
    assert Repo.aggregate(Receipt, :count) == 1
    assert Repo.aggregate(Notification, :count) == 1
    [notification] = Outreach.pending_notifications()
    assert notification.recipient_actor_id == c.sender.id

    assert [{:ok, accepted}] =
             Outreach.dispatch_notifications(fn data ->
               assert data.user.id == c.sender.id
               assert data.message.id == reply.id
               {:ok, %{id: "synthetic-notification"}}
             end)

    assert accepted.state == "accepted"
    assert Outreach.dispatch_notifications(fn _ -> flunk("No repeat notification") end) == []
    other_scope = Accounts.Scope.for_user(c.owner)
    assert {:ok, own_reply} = Outreach.reply_draft(other_scope, draft.conversation_id)
    assert own_reply.owner_id == c.owner.id
    assert own_reply.reply_message_id == reply.id
    assert own_reply.outreach_email == "partner@example.org"
  end

  test "unthreaded inbound falls back to mailbox owner; uncertain notifications never auto resend",
       c do
    assert {:ok, %{messages: [message]}} = Outreach.ingest(incoming("<unrelated@example.org>"))
    [notification] = Outreach.pending_notifications()
    assert notification.recipient_actor_id == c.owner.id
    assert [{:ok, unknown}] = Outreach.dispatch_notifications(fn _ -> {:error, :timeout} end)
    assert unknown.state == "unknown"
    assert Outreach.dispatch_notifications(fn _ -> flunk("No blind retry") end) == []
    assert {:ok, detail} = Outreach.get(c.scope, message.conversation_id)
    assert hd(detail.messages).body_html == "<script>untrusted()</script>"
    refute inspect(Repo.get!(PhoenixCRM.Message, message.id)) =~ "untrusted"
  end

  test "sender and recipient edits create a separate draft conversation and invalidate approval",
       c do
    {:ok, draft} = draft(c.scope)
    {:ok, batch} = Batches.prepare(c.scope, draft, "outreach", [], true)
    {:ok, _} = Batches.approve(c.scope, batch.id)

    assert {:ok, changed} =
             Drafts.save(c.scope, draft, %{"outreach_mailbox_ref" => "outreach_fr"})

    assert changed.edition == "fr"
    refute changed.conversation_id == draft.conversation_id
    assert {:ok, :stale} = Batches.dispatch(c.scope, batch.id)
    refute_receive {:email, _}

    assert {:ok, %{total: 1}} =
             Outreach.list(c.scope, %{
               "mailbox_ref" => "outreach_fr",
               "email" => "partner@example.org"
             })

    assert {:ok, %{total: 0}} = Outreach.list(c.scope, %{"email" => "other@example.org"})

    assert {:error, %Ecto.Changeset{}} =
             Drafts.save(c.scope, changed, %{"recipient_mode" => "contacts"})
  end

  test "body and notification remain durable before attachment failures; manual file retry replays only once",
       c do
    payload =
      incoming("<new@example.org>", %{
        "Attachments" => [
          %{
            "Name" => "synthetic.pdf",
            "ContentType" => "application/pdf",
            "ContentLength" => 12,
            "DownloadToken" => "synthetic-private-token"
          }
        ]
      })

    {:ok, receipt} = Outreach.receive(payload)

    assert {:ok, %{receipt: processed, messages: [message]}} =
             Outreach.process_receipt(receipt.id)

    assert processed.files_pending and processed.state == "processed"
    assert Repo.aggregate(Notification, :count) == 1
    assert {:ok, failed} = Outreach.record_processing_failure(receipt.id, :attachment_expired)
    assert failed.processed_at == processed.processed_at
    assert failed.files_pending and failed.state == "processed"
    assert {:ok, %{messages: []}} = Outreach.process_receipt(receipt.id)
    assert {:ok, detail} = Outreach.get(c.scope, message.conversation_id)
    assert hd(detail.messages).body_text == "A synthetic reply"
    assert {:ok, _} = Outreach.retry_receipt(c.scope, receipt.id)
    assert {:ok, %{messages: [replayed]}} = Outreach.process_receipt(receipt.id)
    assert replayed.id == message.id
    assert replayed.source == message.source
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 1
    assert Repo.aggregate(Notification, :count) == 1
    assert {:ok, complete} = Outreach.complete_attachments(receipt.id)
    refute complete.files_pending
    assert complete.state == "processed"
    assert Outreach.pending_receipts() == []
  end

  test "explicit retry after corrected receiving configuration recovers quarantined input once",
       c do
    payload = incoming("<new@example.org>", %{"Recipients" => ["hello@corrected.pauseai.ca"]})
    {:ok, receipt} = Outreach.receive(payload)
    assert {:ok, %{receipt: quarantined, messages: []}} = Outreach.process_receipt(receipt.id)
    assert quarantined.state == "quarantined" and not is_nil(quarantined.processed_at)

    boxes =
      Enum.map(c.boxes, fn box ->
        if box.id == "outreach_en",
          do: %{
            box
            | receiving_addresses: box.receiving_addresses ++ ["hello@corrected.pauseai.ca"]
          },
          else: box
      end)

    Application.put_env(:pauseai_ca, :outreach_mailboxes, boxes)
    assert {:ok, retried} = Outreach.retry_receipt(c.scope, receipt.id)
    assert retried.processed_at == quarantined.processed_at
    assert {:ok, %{messages: [_message]}} = Outreach.process_receipt(receipt.id)
    assert {:ok, %{messages: []}} = Outreach.process_receipt(receipt.id)
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 1
    assert Repo.aggregate(Notification, :count) == 1
  end

  test "receipt retry is bounded, durable and explicitly administrator recovered", c do
    {:ok, receipt} = Outreach.receive(incoming("<new@example.org>"))

    assert {:ok, first} =
             Outreach.record_processing_failure(receipt.id, :temporary_download_failure)

    assert first.attempts == 1 and first.state == "pending"
    assert Outreach.pending_receipts() == []
    {:ok, _} = Outreach.record_processing_failure(receipt.id, :temporary_download_failure)

    assert {:ok, failed} =
             Outreach.record_processing_failure(receipt.id, :temporary_download_failure)

    assert failed.attempts == 3 and failed.state == "failed"
    assert {:error, :retry_required} = Outreach.process_receipt(receipt.id)
    outsider = user_fixture() |> Accounts.Scope.for_user()
    assert {:error, :unauthorized} = Outreach.retry_receipt(outsider, receipt.id)
    assert {:ok, retried} = Outreach.retry_receipt(c.scope, receipt.id)
    assert retried.state == "pending" and retried.attempts == 0
    assert retried.payload == receipt.payload
    assert {:ok, %{processing: [%{id: id, state: "pending"}]}} = Outreach.list(c.scope)
    assert id == receipt.id
  end

  test "ineligible address and changed verified configuration block delivery", c do
    {:ok, draft} = draft(c.scope)
    {:ok, batch} = Batches.prepare(c.scope, draft, "outreach", [], true)
    {:ok, _} = Batches.approve(c.scope, batch.id)

    Application.put_env(
      :pauseai_ca,
      :outreach_mailboxes,
      Enum.map(c.boxes, &%{&1 | verified?: false})
    )

    assert {:ok, :stale} = Batches.dispatch(c.scope, batch.id)
    refute_receive {:email, _}
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 0
  end
end
