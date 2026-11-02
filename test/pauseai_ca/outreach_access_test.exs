defmodule PauseAiCa.OutreachAccessTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Outreach}
  alias PauseAiCa.Outreach.{Access, MailboxGrantEvent, Notification}
  alias PauseAiCa.Newsletters.{Batches, Drafts, Delivery}
  alias PauseAiCa.Volunteers.{Group, Manager}

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    manager = user_fixture() |> change(superadmin: false) |> Repo.update!()
    ordinary = user_fixture() |> change(superadmin: false) |> Repo.update!()
    group = Repo.insert!(%Group{name: "Synthetic mailbox managers"})
    membership = Repo.insert!(%Manager{group_id: group.id, user_id: manager.id})

    boxes =
      Enum.map(
        [
          {"outreach_en", "en", "hello@example.org"},
          {"outreach_fr", "fr", "bonjour@example.org"}
        ],
        fn {id, locale, email} ->
          %{
            id: id,
            name: "Synthetic mailbox",
            email: email,
            locale: locale,
            owner_id: admin.id,
            enabled?: true,
            verified?: true,
            receiving_addresses: ["receive-#{locale}@example.org"]
          }
        end
      )

    previous = Application.get_env(:pauseai_ca, :outreach_mailboxes)
    environment = Application.get_env(:pauseai_ca, :mail_environment)
    Application.put_env(:pauseai_ca, :outreach_mailboxes, boxes)
    Application.put_env(:pauseai_ca, :mail_environment, :test)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pauseai_ca, :outreach_mailboxes, previous),
        else: Application.delete_env(:pauseai_ca, :outreach_mailboxes)

      Application.put_env(:pauseai_ca, :mail_environment, environment)
    end)

    for user <- [admin, manager, ordinary] do
      email = user.email
      assert_receive {:email, %{to: [{_, ^email}]}}
    end

    %{
      admin: admin,
      manager: manager,
      ordinary: ordinary,
      group: group,
      membership: membership,
      admin_scope: Accounts.Scope.for_user(admin),
      scope: Accounts.Scope.for_user(manager)
    }
  end

  defp draft(scope, attrs \\ %{}) do
    Outreach.create_draft(
      scope,
      Map.merge(
        %{
          "mailbox_ref" => "outreach_en",
          "email" => "partner@example.org",
          "subject" => "Synthetic delegation",
          "source" => "A synthetic proposal.\n\nSynthetic"
        },
        attrs
      )
    )
  end

  defp incoming(locale, attrs \\ %{}) do
    %{
      "items" => [
        Map.merge(
          %{
            "Uuid" => [Ecto.UUID.generate()],
            "MessageId" => "<#{Ecto.UUID.generate()}@example.org>",
            "From" => %{"Address" => "partner@example.org"},
            "Recipients" => ["receive-#{locale}@example.org"],
            "To" => [
              %{
                "Address" =>
                  if(locale == "en", do: "hello@example.org", else: "bonjour@example.org")
              }
            ],
            "Subject" => "Synthetic reply",
            "SentAtDate" => "Mon, 02 Nov 2026 00:00:00 +0000",
            "RawTextBody" => "Synthetic reply",
            "Attachments" => []
          },
          attrs
        )
      ]
    }
  end

  test "only admins delegate to existing confirmed managers; revisions and immutable actor audit survive revocation",
       c do
    assert {:ok, []} = Outreach.mailboxes(c.scope)
    assert {:error, :unauthorized} = Outreach.mailboxes(Accounts.Scope.for_user(c.ordinary))

    assert {:error, :not_eligible} =
             Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.ordinary.id, 0)

    assert {:error, :unauthorized} =
             Outreach.grant_mailbox(c.scope, "outreach_en", c.manager.id, 0)

    assert {:ok, grant} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 0)
    assert grant.revision == 1
    assert {:ok, [%{id: "outreach_en"}]} = Outreach.mailboxes(c.scope)

    assert {:error, :mailbox_unavailable} =
             Outreach.list(c.scope, %{"mailbox_ref" => "outreach_fr"})

    assert {:error, :stale} =
             Outreach.revoke_mailbox(c.admin_scope, "outreach_en", c.manager.id, 0)

    assert {:ok, revoked} = Outreach.revoke_mailbox(c.admin_scope, "outreach_en", c.manager.id, 1)
    assert revoked.revision == 2 and revoked.revoked_at
    assert {:ok, restored} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 2)
    assert restored.revision == 3

    assert Enum.map(
             Repo.all(from(e in MailboxGrantEvent, order_by: e.revision)),
             &{&1.action, &1.actor_id}
           ) ==
             [{"granted", c.admin.id}, {"revoked", c.admin.id}, {"granted", c.admin.id}]

    refute Repo.get!(Accounts.User, c.manager.id).superadmin

    assert {:ok, %{eligible_managers: [%{id: id}], grants: [_]}} =
             Outreach.mailbox_access(c.admin_scope)

    assert id == c.manager.id
    assert {:error, :unauthorized} = Outreach.mailbox_access(c.scope)
  end

  test "a manager composes and sends only its granted identity without gaining CRM/newsletter authority",
       c do
    assert {:ok, _} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 0)
    assert {:ok, draft} = draft(c.scope)
    assert {:error, :mailbox_unavailable} = draft(c.scope, %{"mailbox_ref" => "outreach_fr"})
    assert {:error, :unauthorized} = PauseAiCa.CRM.directory_page(c.scope, %{})
    assert {:error, :unauthorized} = PauseAiCa.Newsletters.audience(c.scope)
    assert {:error, :unauthorized} = Drafts.create(c.scope)
    assert {:error, _} = Drafts.save(c.scope, draft, %{"outreach_mailbox_ref" => "outreach_fr"})
    assert {:ok, [saved]} = Drafts.list(c.scope)
    assert saved.id == draft.id
    assert {:ok, batch} = Batches.prepare(c.scope, draft, "outreach", [], true)
    assert {:ok, _} = Batches.approve(c.scope, batch.id)
    assert {:ok, :completed} = Batches.dispatch(c.scope, batch.id)
    assert_receive {:email, %{from: {_, "hello@example.org"}, to: [{_, "partner@example.org"}]}}
    delivery = Repo.get_by!(Delivery, batch_id: batch.id)
    assert delivery.state == "accepted" and delivery.authorizing_admin_id == c.manager.id
    archived = Repo.get_by!(PhoenixCRM.Message, delivery_ref: delivery.id)
    assert archived.actor_id == c.manager.id and archived.mailbox_ref == "outreach_en"
  end

  test "revocation denies reads/save/send; regrant cannot resurrect a prepared approval or erase draft content",
       c do
    {:ok, _} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 0)
    {:ok, draft} = draft(c.scope)
    {:ok, batch} = Batches.prepare(c.scope, draft, "outreach", [], true)
    {:ok, _} = Batches.approve(c.scope, batch.id)
    {:ok, _} = Outreach.revoke_mailbox(c.admin_scope, "outreach_en", c.manager.id, 1)
    assert {:error, :unauthorized} = Drafts.get(c.scope, draft.id)
    assert {:error, :unauthorized} = Drafts.save(c.scope, draft, %{"subject" => "Forbidden"})
    assert {:error, :unauthorized} = Batches.dispatch(c.scope, batch.id)
    assert Repo.get!(PauseAiCa.Newsletters.Draft, draft.id).source == draft.source
    {:ok, _} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 2)
    assert {:ok, :stale} = Batches.dispatch(c.scope, batch.id)
    assert Repo.get_by!(Delivery, batch_id: batch.id).attempted_at == nil
    refute_receive {:email, _}
    {:ok, fresh} = Batches.prepare(c.scope, draft, "outreach", [], true)
    assert fresh.id != batch.id
  end

  test "removing and restoring the last manager role invalidates old approval independently of grant revision",
       c do
    {:ok, _} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 0)
    {:ok, draft} = draft(c.scope)
    {:ok, batch} = Batches.prepare(c.scope, draft, "outreach", [], true)
    Repo.delete!(c.membership)
    assert {:error, :unauthorized} = Drafts.get(c.scope, draft.id)
    Repo.insert!(%Manager{group_id: c.group.id, user_id: c.manager.id})
    assert {:ok, _} = Drafts.get(c.scope, draft.id)
    assert {:error, :stale} = Batches.approve(c.scope, batch.id)
  end

  test "mixed or unknown provider receipts cannot reveal status or retry through a single grant",
       c do
    {:ok, _} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 0)
    en = incoming("en")
    fr = incoming("fr")
    mixed = %{"items" => en["items"] ++ fr["items"]}
    unknown = incoming("en", %{"Recipients" => ["unknown@example.org"]})

    receipts =
      for payload <- [en, mixed, unknown] do
        {:ok, receipt} = Outreach.receive(payload)
        Repo.update!(change(receipt, state: "failed"))
      end

    [one, both, unknown] = receipts
    assert Enum.map(Outreach.Ingestion.processing(c.scope), & &1.id) == [one.id]
    assert {:ok, _} = Outreach.retry_receipt(c.scope, one.id)
    assert {:error, :unauthorized} = Outreach.retry_receipt(c.scope, both.id)
    assert {:error, :unauthorized} = Outreach.retry_receipt(c.scope, unknown.id)
    {:ok, _} = Outreach.grant_mailbox(c.admin_scope, "outreach_fr", c.manager.id, 0)
    assert {:ok, _} = Outreach.retry_receipt(c.scope, both.id)
    assert {:error, :unauthorized} = Outreach.retry_receipt(c.scope, unknown.id)
  end

  test "a pending reply notification falls back to the existing owner after the submitting manager loses access",
       c do
    {:ok, _} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 0)
    {:ok, draft} = draft(c.scope)
    {:ok, batch} = Batches.prepare(c.scope, draft, "outreach", [], true)
    {:ok, _} = Batches.approve(c.scope, batch.id)
    {:ok, :completed} = Batches.dispatch(c.scope, batch.id)
    assert_receive {:email, _}
    sent = Repo.get_by!(PhoenixCRM.Message, conversation_id: draft.conversation_id)
    {:ok, _} = Outreach.ingest(incoming("en", %{"InReplyTo" => sent.rfc_message_id}))
    notification = Repo.one!(Notification)
    assert notification.recipient_actor_id == c.manager.id
    {:ok, _} = Outreach.revoke_mailbox(c.admin_scope, "outreach_en", c.manager.id, 1)
    parent = self()

    Outreach.dispatch_notifications(fn %{user: user} ->
      send(parent, {:notified, user.id})
      {:ok, %{id: "synthetic"}}
    end)

    assert_receive {:notified, id}
    assert id == c.admin.id
    assert Repo.get!(Notification, notification.id).state == "accepted"
    assert Repo.get!(Notification, notification.id).recipient_actor_id == c.admin.id
  end

  test "separately committed same-second authority changes cannot restore old approval evidence" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      user =
        Repo.insert!(%Accounts.User{
          email: "synthetic-xmin-#{Ecto.UUID.generate()}@example.org",
          superadmin: true,
          confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      try do
        scope = Accounts.Scope.for_user(user)
        assert {:ok, before} = Access.fingerprint(scope, "outreach_en")

        {1, _} =
          Repo.update_all(from(u in Accounts.User, where: u.id == ^user.id),
            set: [superadmin: false, updated_at: user.updated_at]
          )

        assert {:error, :unauthorized} = Access.fingerprint(scope, "outreach_en")

        {1, _} =
          Repo.update_all(from(u in Accounts.User, where: u.id == ^user.id),
            set: [superadmin: true, updated_at: user.updated_at]
          )

        assert Repo.get!(Accounts.User, user.id).updated_at == user.updated_at
        assert {:ok, restored} = Access.fingerprint(scope, "outreach_en")
        assert restored != before
      after
        Repo.delete_all(from(u in Accounts.User, where: u.id == ^user.id))
      end
    end)
  end
end
