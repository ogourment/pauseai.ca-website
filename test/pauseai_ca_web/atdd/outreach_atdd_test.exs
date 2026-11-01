if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.OutreachTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    import Ecto.Query, only: [from: 2]
    alias PauseAiCa.{Accounts, Newsletters, Outreach, Repo}
    alias PauseAiCaWeb.AtddEvidence

    # Contract provenance: private acceptance_harness 9e060c03162810781052000cea663750f11605cc,
    # docs/acceptance-contract.md and docs/approval_review_bundle_example.md;
    # approved OUTREACH-01–03 in the private guide docs/outreach-20261031/index.html.
    # All accounts/messages are synthetic. Swoosh.Test is the only outbound transport.
    @moduletag :atdd
    @scenarios (for {area, title} <- [
                      {"01", "Compose, save, review and explicitly send an attributed message"},
                      {"02", "Receive once, notify the sending admin and reply as another admin"}
                    ],
                    {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "OUTREACH-#{area}-#{locale}",
                    title: "OUTREACH-#{area} · #{title} · #{language}",
                    tags: ["mail", "outreach", "superadmin"],
                    roles: ["Email administrator", "External correspondent"],
                    language: language,
                    device: device,
                    surface: "LiveView",
                    host_os: "Linux",
                    theme: "light",
                    source_file: __ENV__.file
                  }
                end) ++
                 [
                   %{
                     id: "OUTREACH-03",
                     title:
                       "OUTREACH-03 · Optional signature ignores quoted previous correspondence",
                     tags: ["mail", "outreach", "superadmin"],
                     roles: ["Email administrator"],
                     language: "English",
                     device: "Desktop",
                     surface: "LiveView",
                     host_os: "Linux",
                     theme: "light",
                     source_file: __ENV__.file
                   }
                 ]

    setup_all do
      AtddEvidence.reset!("OUTREACH-01–03 · Authored partnership mail", @scenarios, %{
        browser: "Chromium",
        viewport: "1280×900 desktop / 390×844 phone",
        surface: "LiveView",
        host_os: "Linux",
        theme: "light"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      previous =
        for key <- [
              :outreach_mailboxes,
              :outreach_webhook_token,
              :outreach_inbound_enabled,
              :outreach_worker_enabled,
              :mail_environment
            ],
            into: %{},
            do: {key, Application.get_env(:pauseai_ca, key)}

      old_process = Application.get_env(:swoosh, :shared_test_process)
      Application.put_env(:swoosh, :shared_test_process, self())
      Application.put_env(:pauseai_ca, :mail_environment, :test)

      Application.put_env(
        :pauseai_ca,
        :outreach_webhook_token,
        "SyntheticOutreachWebhookOnly123456789"
      )

      Application.put_env(:pauseai_ca, :outreach_inbound_enabled, true)
      Application.put_env(:pauseai_ca, :outreach_worker_enabled, false)

      on_exit(fn ->
        Enum.each(previous, fn {key, value} ->
          if is_nil(value),
            do: Application.delete_env(:pauseai_ca, key),
            else: Application.put_env(:pauseai_ca, key, value)
        end)

        if is_nil(old_process),
          do: Application.delete_env(:swoosh, :shared_test_process),
          else: Application.put_env(:swoosh, :shared_test_process, old_process)
      end)

      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "OUTREACH-01 authored message #{locale}", c do
        locale = unquote(locale)
        id = "OUTREACH-01-#{locale}"
        %{sender: sender} = actors(locale)
        baseline = unrelated_counts()
        {b, draft, email, archived} = compose_and_send(c.conn, sender, locale, id)

        b =
          b
          |> show_email(email)
          |> capture(
            id,
            "External correspondent reads the actual captured message",
            "The chosen From, exact single recipient, authored text and signature were delivered to Swoosh.Test"
          )

        assert email.from == sender_identity(locale)
        assert email.to == [{"", recipient(locale)}]
        assert email.cc == [] and email.bcc == []
        assert email.text_body =~ "Synthetic partnership discussion #{locale}"
        assert email.text_body =~ "Alice"
        assert archived.actor_id == sender.id
        assert archived.outcome == :accepted
        assert archived.source["markdown"] == Repo.get!(Newsletters.Draft, draft.id).source
        assert archived.envelope["from"] == elem(sender_identity(locale), 1)
        assert archived.envelope["to"] == [recipient(locale)]

        # A later authored edit must not rewrite the already submitted archive.
        b =
          b
          |> visit(draft_path(draft, locale))
          |> connected()
          |> fill_in(tr(locale, "Message · Markdown"), with: "Later unsent content")
          |> click_button(tr(locale, "Save"))
          |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)
          |> capture(
            id,
            "Edit and save after sending",
            "The new draft remains unsent; the earlier sent record stays immutable"
          )

        assert Repo.get!(PhoenixCRM.Message, archived.id).body_text == archived.body_text
        refute_receive {:email, _}

        b =
          b
          |> click_link(tr(locale, "View conversation"))
          |> connected()
          |> assert_has("#outreach-messages", text: "Synthetic partnership discussion #{locale}")
          |> refute_has("#outreach-messages", text: "Later unsent content")
          |> assert_has("#outreach-messages", text: "Alice Example")
          |> capture(
            id,
            "Open the conversation from the edited draft",
            "The frozen sent text and actual submitting administrator remain visible"
          )

        b
        |> reload_current()
        |> connected()
        |> assert_has("#outreach-messages", text: "Alice Example")
        |> capture(
          id,
          "Reload the shared conversation",
          "Attribution and the original content persist without another submission"
        )

        assert unrelated_counts() == baseline
        assert Repo.aggregate(PhoenixCRM.Message, :count) == 1
        assert Repo.aggregate(Newsletters.Delivery, :count) == 1
        refute_receive {:email, _}
        finish(id)
      end

      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "OUTREACH-02 incoming and delegated reply #{locale}", c do
        locale = unquote(locale)
        id = "OUTREACH-02-#{locale}"
        %{sender: sender, colleague: colleague, owner: owner} = actors(locale)
        baseline = unrelated_counts()
        {b, draft, outgoing, archived} = compose_and_send(c.conn, sender, locale, id)
        assert sender.id != owner.id
        assert outgoing.from == sender_identity(locale)
        payload = inbound_payload(locale, archived.rfc_message_id)

        pending(
          id,
          "Receive the provider callback",
          "Authenticated intake durably queues one synthetic incoming reply before acknowledgement"
        )

        callback = callback(payload)
        assert callback.status == 202
        [receipt] = Outreach.pending_receipts()
        assert receipt.state == "pending"
        assert Repo.aggregate(PhoenixCRM.Message, :count) == 1
        process_inbound()
        assert Repo.get!(PauseAiCa.Outreach.Receipt, receipt.id).state == "processed"
        inbound = Repo.one!(from m in PhoenixCRM.Message, where: m.direction == :inbound)
        assert inbound.conversation_id == draft.conversation_id

        assert inbound.body_text ==
                 "Synthetic partner reply #{locale}. Please discuss next steps."

        assert Repo.aggregate(PhoenixCRM.Conversation, :count) == 1
        assert Repo.aggregate(PhoenixCRM.Address, :count) == 1
        assert unrelated_counts() == baseline
        assert_receive {:email, notification}, 8_000

        assert notification.to == [{"", sender.email}] or
                 notification.to == [{sender.name, sender.email}]

        refute Enum.any?(notification.to, fn {_, email} -> email == owner.email end)
        assert notification.cc == [] and notification.bcc == []
        reply_path = "/manage/mail/conversations/#{draft.conversation_id}?locale=#{locale}"
        assert notification.html_body =~ reply_path
        refute notification.html_body =~ "Synthetic partner reply"
        refute notification.html_body =~ "tracking.example.org"

        b =
          b
          |> show_email(notification)
          |> capture(
            id,
            "Original sending administrator reads the actual notification",
            "Only that administrator receives a login-required conversation link; incoming body and tracking images are absent"
          )
          |> click_link(notification_label(locale))
          |> connected()
          |> assert_has("#outreach-messages", text: "Synthetic partner reply #{locale}")
          |> refute_has("#outreach-messages img")
          |> capture(
            id,
            "Follow the notification's conversation control",
            "The reply appears under the exact previously submitted thread"
          )

        b =
          b
          |> reload_current()
          |> connected()
          |> assert_has("#outreach-messages", text: "Synthetic partner reply #{locale}")
          |> capture(
            id,
            "Reload the received conversation",
            "The durable incoming message survives reload"
          )

        assert callback(payload).status == 202
        process_inbound()
        assert Repo.aggregate(PhoenixCRM.Message, :count) == 2
        assert Repo.aggregate(PauseAiCa.Outreach.Notification, :count) == 1
        refute_receive {:email, _}

        # Use a separate browser identity, then navigate the actual Inbox controls.
        b =
          switch_browser_identity(b, &login(&1, colleague))
          |> visit("/manage/mail?locale=#{locale}")
          |> connected()
          |> capture(
            id,
            "A second authorized administrator opens Emails",
            "The Inbox control is available without impersonating the original sender"
          )
          |> click_link("[data-navigation-item='mail.conversations']", tr(locale, "Inbox"))
          |> connected()
          |> capture(
            id,
            "Open Inbox",
            "The shared conversation is visible to the second administrator"
          )
          |> click_link(nil, "Synthetic partnership #{locale}", exact: false)
          |> connected()
          |> capture(
            id,
            "Open the shared conversation",
            "Reply uses this administrator's own draft and permissions"
          )
          |> click_button(tr(locale, "Reply"))
          |> connected()
          |> assert_has("#newsletter-draft-form")
          |> fill_in(tr(locale, "Message · Markdown"),
            with: "Synthetic colleague reply #{locale}\n\nBob"
          )
          |> click_button(tr(locale, "Save"))
          |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)

        {:ok, [reply]} = Newsletters.Drafts.list(Accounts.Scope.for_user(colleague))
        assert reply.owner_id == colleague.id
        assert reply.conversation_id == draft.conversation_id
        assert reply.reply_message_id == inbound.id

        b =
          b
          |> capture(
            id,
            "Second administrator saves a reply in the standard editor",
            "The same conversation is retained with a distinct draft owner"
          )
          |> review_and_send(locale, id)

        assert_receive {:email, answer}, 8_000
        assert answer.from == sender_identity(locale)
        assert answer.to == [{"", recipient(locale)}]
        assert answer.text_body =~ "Synthetic colleague reply #{locale}"
        assert Map.new(answer.headers)["In-Reply-To"] == inbound.rfc_message_id

        submitted =
          Repo.one!(
            from m in PhoenixCRM.Message,
              where: m.direction == :outbound and m.actor_id == ^colleague.id
          )

        assert submitted.outcome == :accepted
        assert submitted.conversation_id == draft.conversation_id

        b =
          b
          |> show_email(answer)
          |> capture(
            id,
            "External correspondent reads the second administrator's captured reply",
            "The mailbox From stays consistent while stored attribution records Bob"
          )
          |> visit(draft_path(reply, locale))
          |> connected()
          |> click_link(tr(locale, "View conversation"))
          |> connected()
          |> assert_has("#outreach-messages", text: "Bob Example")
          |> capture(
            id,
            "Return to the conversation",
            "Original message, received reply and Bob's sent reply form one persistent history"
          )

        colleague |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

        b
        |> click_button(tr(locale, "Reply"))
        |> assert_path("/dashboard")
        |> connected()
        |> refute_has("#newsletter-draft-form")
        |> capture(
          id,
          "Revoke Bob's email administration and press Reply",
          "Fresh authorization denies another draft"
        )

        b =
          switch_browser_identity(b, & &1)
          |> visit(reply_path)
          |> assert_path("/users/log-in")
          |> assert_has("form")
          |> refute_has("#outreach-messages")
          |> capture(
            id,
            "A signed-out recipient opens the notification URL",
            "Authentication is required before private conversation content can be read"
          )

        assert Repo.aggregate(PhoenixCRM.Message, :count) == 3
        assert unrelated_counts() == baseline
        refute_receive {:email, _}
        _ = b
        finish(id)
      end
    end

    @tag screenshot: true
    @tag browser_context_opts: [viewport: %{width: 1280, height: 900}]
    test "OUTREACH-03 signature is optional and quoted old signatures do not satisfy it", c do
      id = "OUTREACH-03"
      %{sender: sender} = actors("en")

      b =
        c.conn
        |> login(sender)
        |> open_new_draft("en", id)
        |> fill_in("Subject", with: "Signature guidance")
        |> fill_in("Message · Markdown",
          with: "Fresh unsigned message\n\n> Previous message\n> Alice"
        )
        |> click_button("Save")
        |> assert_has("#newsletter-save-status", text: "Saved", exact: true)
        |> assert_has("#outreach-signature-hint", text: "Suggested signature: Alice")
        |> capture(
          id,
          "Save a fresh message above quoted previous correspondence",
          "The quoted old signature does not count; the saved source is unchanged"
        )

      {:ok, [draft]} = Newsletters.Drafts.list(Accounts.Scope.for_user(sender))
      assert draft.source == "Fresh unsigned message\n\n> Previous message\n> Alice"
      assert Repo.aggregate(PhoenixCRM.Message, :count) == 0

      b =
        b
        |> check("I reviewed these contacts’ eligibility for this invitation or message.")
        |> click_button("Review & send")
        |> assert_has("#newsletter-batch-review")
        |> capture(
          id,
          "Prepare review while the new message remains unsigned",
          "Signature guidance does not block the ordinary review flow or change the frozen content"
        )
        |> click_button("Back to editing")

      b =
        b
        |> fill_in("Message · Markdown", with: "Fresh unsigned message")
        |> click_button("Save")
        |> assert_has("#newsletter-save-status", text: "Saved", exact: true)
        |> click_button("Add signature")
        |> assert_has("#newsletter-save-status", text: "Unsaved changes", exact: true)
        |> capture(
          id,
          "Explicitly choose Add signature",
          "The first name is added only to the unsaved draft; sending remains a separate action"
        )

      assert Repo.get!(Newsletters.Draft, draft.id).source == "Fresh unsigned message"

      b
      |> click_button("Save")
      |> assert_has("#newsletter-save-status", text: "Saved", exact: true)
      |> reload_current()
      |> connected()
      |> refute_has("button", text: "Add signature", exact: true)
      |> capture(
        id,
        "Save and reload the explicitly signed draft",
        "The source retains the chosen signature with no submitted mail"
      )

      assert Repo.get!(Newsletters.Draft, draft.id).source == "Fresh unsigned message\n\nAlice"
      assert Repo.aggregate(PhoenixCRM.Message, :count) == 0
      refute_receive {:email, _}
      finish(id)
    end

    defp actors(locale) do
      owner = admin("owner-#{locale}@example.org", "Morgan Owner")
      sender = admin("sender-#{locale}@example.org", "Alice Example")
      colleague = admin("colleague-#{locale}@example.org", "Bob Example")

      for actor <- [sender, colleague] do
        {:ok, _} =
          Newsletters.Edition.confirm_preference(
            Accounts.Scope.for_user(actor),
            actor.email,
            locale
          )
      end

      boxes =
        for edition <- ["en", "fr"] do
          {name, address} = sender_identity(edition)

          %{
            id: "outreach_#{edition}",
            name: name,
            email: address,
            locale: edition,
            owner_id: owner.id,
            receiving_addresses: [receiving_address(edition)],
            enabled?: true,
            verified?: true
          }
        end

      Application.put_env(:pauseai_ca, :outreach_mailboxes, boxes)
      flush_emails()
      %{owner: owner, sender: sender, colleague: colleague}
    end

    defp admin(email, name),
      do:
        user_fixture(%{email: email})
        |> Ecto.Changeset.change(superadmin: true, name: name)
        |> Repo.update!()

    defp compose_and_send(browser, sender, locale, id) do
      baseline = unrelated_counts()

      body =
        "## Synthetic partnership discussion #{locale}\n\nCould we discuss a synthetic local event?"

      b =
        browser
        |> login(sender)
        |> open_new_draft(locale, id)
        |> fill_in(tr(locale, "Subject"), with: "Synthetic partnership #{locale}")
        |> fill_in(tr(locale, "Message · Markdown"), with: body)
        |> click_button(tr(locale, "Save"))
        |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)
        |> assert_has("#outreach-signature-hint", text: "Alice")
        |> capture(
          id,
          "Write and save through the existing Markdown composer",
          "The unsigned source persists and a nonblocking first-name suggestion appears"
        )

      {:ok, [draft]} = Newsletters.Drafts.list(Accounts.Scope.for_user(sender))
      assert draft.source == body
      assert draft.edition == locale
      assert Repo.aggregate(PhoenixCRM.Message, :count) == 0
      refute_receive {:email, _}

      b =
        b
        |> visit(draft_path(draft, locale))
        |> connected()
        |> assert_has("#outreach-signature-hint", text: "Alice")
        |> capture(
          id,
          "Reload the saved draft",
          "Subject, exact recipient, whitelisted From and unsigned source survive reload"
        )
        |> click_button(tr(locale, "Add signature"))
        |> assert_has("#newsletter-save-status", text: tr(locale, "Unsaved changes"), exact: true)
        |> click_button(tr(locale, "Save"))
        |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)
        |> capture(
          id,
          "Choose Add signature, then Save",
          "Only the explicit action appends Alice; the draft is still unsent"
        )

      assert Repo.get!(Newsletters.Draft, draft.id).source == body <> "\n\nAlice"
      refute_receive {:email, _}
      b = review_and_send(b, locale, id)
      assert_receive {:email, email}, 8_000
      archived = Repo.one!(from m in PhoenixCRM.Message, where: m.direction == :outbound)
      assert archived.actor_id == sender.id and archived.outcome == :accepted
      assert unrelated_counts() == baseline
      {b, draft, email, archived}
    end

    defp open_new_draft(b, locale, id) do
      b =
        b
        |> visit("/manage/mail?locale=#{locale}")
        |> connected()
        |> capture(
          id,
          "Authorized administrator opens Emails",
          "Use the visible Inbox navigation control"
        )

      pending(
        id,
        "Click Inbox",
        "The authored-mail inbox opens under the existing Emails workspace"
      )

      b =
        b
        |> click_link("[data-navigation-item='mail.conversations']", tr(locale, "Inbox"))
        |> connected()
        |> assert_has("#outreach-workspace")
        |> capture(
          id,
          "Click Inbox",
          "The mailbox filters and Compose outreach email control are available"
        )
        |> click("#outreach-compose > summary")
        |> capture(
          id,
          "Expand Compose outreach email",
          "Choose a configured From and one exact external recipient"
        )
        |> select(tr(locale, "From"), option: sender_option(locale))
        |> fill_in(tr(locale, "To"), with: recipient(locale))
        |> fill_in(tr(locale, "Subject"), with: "Synthetic partnership #{locale}")
        |> click_button(tr(locale, "Open draft"))
        |> connected()
        |> assert_has("#newsletter-draft-form")
        |> capture(
          id,
          "Open draft from Inbox",
          "The existing shared Markdown editor, preview and Save flow are reused"
        )

      assert Repo.aggregate(PhoenixCRM.Message, :count) == 0
      refute_receive {:email, _}
      b
    end

    defp review_and_send(b, locale, id) do
      b =
        b
        |> check(
          tr(locale, "I reviewed these contacts’ eligibility for this invitation or message.")
        )
        |> capture(
          id,
          "Confirm communication eligibility",
          "Review & send remains an explicit next action"
        )
        |> click_button(tr(locale, "Review & send"))
        |> assert_has("#newsletter-batch-review", text: recipient(locale))
        |> assert_has("#newsletter-batch-review", text: elem(sender_identity(locale), 1))
        |> assert_has("#newsletter-batch-review",
          text: tr(locale, "Message and recipients to send")
        )
        |> capture(
          id,
          "Open Review & send",
          "The frozen body, recipient, mailbox sender and current administrator are visible before Send now"
        )

      refute_receive {:email, _}

      b
      |> click_button(tr(locale, "Send now"))
      |> assert_has("#newsletter-delivery-progress", text: "1 / 1", timeout: 30_000)
      |> assert_has("#newsletter-delivery-progress",
        text: tr(locale, "Completed"),
        timeout: 30_000
      )
      |> capture(
        id,
        "Explicitly choose Send now",
        "One durable local acceptance receipt and one attributed CRM message result"
      )
    end

    defp inbound_payload(locale, rfc_id) do
      %{
        "items" => [
          %{
            "Uuid" => [Ecto.UUID.generate()],
            "MessageId" => "<reply-#{Ecto.UUID.generate()}@partner.example>",
            "InReplyTo" => rfc_id,
            "From" => %{"Name" => "Synthetic Partner", "Address" => recipient(locale)},
            "Recipients" => [receiving_address(locale)],
            "To" => [%{"Address" => elem(sender_identity(locale), 1)}],
            "Cc" => [],
            "ReplyTo" => nil,
            "SentAtDate" => "Sat, 31 Oct 2026 12:30:00 +0000",
            "Subject" => "Re: Synthetic partnership #{locale}",
            "RawTextBody" => "Synthetic partner reply #{locale}. Please discuss next steps.",
            "RawHtmlBody" =>
              "<img src='https://tracking.example.org/pixel'><script>alert('untrusted')</script>",
            "ExtractedMarkdownMessage" =>
              "Synthetic partner reply #{locale}. Please discuss next steps.",
            "Headers" => %{"References" => rfc_id},
            "Attachments" => []
          }
        ]
      }
    end

    defp callback(payload) do
      Phoenix.ConnTest.build_conn(:post, "/webhooks/brevo/inbound", Jason.encode!(payload))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("authorization", "Bearer SyntheticOutreachWebhookOnly123456789")
      |> PauseAiCaWeb.Endpoint.call(PauseAiCaWeb.Endpoint.init([]))
    end

    defp process_inbound, do: PauseAiCa.OutreachProvider.process_once()
    defp connected(b), do: assert_has(b, "[data-phx-main].phx-connected")

    defp login(b, actor) do
      {token, _} = generate_user_magic_link_token(actor)

      b
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp draft_path(draft, locale), do: "/manage/mail/drafts/#{draft.id}?locale=#{locale}"
    defp recipient(locale), do: "partner-#{locale}@example.org"
    defp receiving_address("en"), do: "hello@inbound.example.org"
    defp receiving_address("fr"), do: "bonjour@inbound.example.net"
    defp sender_identity("en"), do: {"PauseAI Canada", "hello@pauseai.ca"}
    defp sender_identity("fr"), do: {"PauseIA Canada", "bonjour@pauseia.ca"}

    defp sender_option(locale) do
      {name, email} = sender_identity(locale)
      "#{name} <#{email}>"
    end

    defp notification_label("en"), do: "Read and reply"
    defp notification_label("fr"), do: "Lire et répondre"

    defp reload_current(b) do
      b
      |> evaluate("location.href", &Process.put(:outreach_reload_url, &1))
      |> visit(Process.get(:outreach_reload_url))
    end

    defp unrelated_counts do
      %{
        accounts: Repo.aggregate(Accounts.User, :count),
        confirmed_subscriptions:
          Repo.aggregate(
            from(s in Newsletters.Subscription, where: not is_nil(s.confirmed_at)),
            :count
          ),
        invitations: Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count)
      }
    end

    defp show_email(b, email) do
      escape = fn value ->
        value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      end

      body = email.html_body || "<pre>#{escape.(email.text_body || "")}</pre>"

      body =
        Regex.replace(~r/<img\b[^>]*>/iu, body, "<span>[Image omitted in captured reader]</span>")

      html = """
      <html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
      <style>body{margin:0;background:#eee;font:16px/1.5 system-ui}header{background:#171717;color:white;padding:20px}section{padding:20px;background:white;max-width:850px;margin:20px auto}h1{font-size:22px}dt{font-weight:bold}dd{margin:0 0 10px}a{overflow-wrap:anywhere}</style>
      <header>Captured test inbox · Actual Swoosh.Test delivery · Images disabled · No external transport</header>
      <section id="delivered-email"><h1>#{escape.(email.subject)}</h1><dl><dt>From</dt><dd>#{escape.(inspect(email.from))}</dd><dt>To</dt><dd>#{escape.(inspect(email.to))}</dd><dt>Cc / Bcc</dt><dd>#{escape.(inspect(email.cc))} / #{escape.(inspect(email.bcc))}</dd></dl>#{body}</section></html>
      """

      visit(b, "data:text/html;base64," <> Base.encode64(html))
    end

    defp capture(b, id, trigger, outcome) do
      step = Process.get({:outreach_step, id}, 0) + 1
      name = "#{id}-#{String.pad_leading(to_string(step), 2, "0")}.png"
      evaluate(b, "location.href", &Process.put(:outreach_url, AtddEvidence.safe_url(&1)))
      url = Process.get(:outreach_url)
      IO.puts("Capture URL: #{url}")
      b = AtddEvidence.capture_full_page(b, name)

      AtddEvidence.record_step(name, trigger, outcome, %{
        "scenario_id" => id,
        "step" => step,
        "current_url" => url,
        "trigger" => trigger,
        "expected_outcome" => outcome,
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(b)),
        "geometry" => Process.get(:evidence_geometry),
        "surface" => "LiveView / captured test email",
        "host_os" => "Linux",
        "theme" => "light",
        "external_systems" =>
          "Synthetic Brevo-shaped callback to local authenticated app endpoint; Swoosh.Test outbound capture only; PostgreSQL sandbox rollback. No live provider, real mailbox, DNS, payment or network attachment fetch."
      })

      Process.put({:outreach_step, id}, step)
      b
    end

    defp pending(id, trigger, outcome) do
      step = Process.get({:outreach_step, id}, 0) + 1
      name = "#{id}-#{String.pad_leading(to_string(step), 2, "0")}.png"

      AcceptanceHarness.Evidence.record_pending_step(name, trigger, outcome, %{
        "scenario_id" => id,
        "step" => step
      })
    end

    defp finish(id),
      do: AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp flush_emails do
      receive do
        {:email, _} -> flush_emails()
      after
        0 -> :ok
      end
    end
  end
end
