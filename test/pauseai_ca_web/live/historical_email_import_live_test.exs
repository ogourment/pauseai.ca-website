defmodule PauseAiCaWeb.HistoricalEmailImportLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Repo}
  alias PauseAiCa.Outreach.HistoricalImport

  defp email(id \\ "historical-1") do
    "From: Jeremy Example <jeremy@example.org>\r\nTo: Alice <alice@example.org>, unknown@example.org\r\n" <>
      "Date: Sun, 8 Nov 2026 10:00:00 -0500\r\nMessage-ID: <#{id}@example.org>\r\n" <>
      "Subject: Montréal march\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nHello Montréal!"
  end

  setup do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    assert_receive {:email, _}
    person = Repo.insert!(%PhoenixCRM.Person{name: "Alice Example", city: "Montréal"})
    address = Repo.insert!(%PhoenixCRM.Address{email: "alice@example.org", person_id: person.id})
    old = Application.get_env(:pauseai_ca, :outreach_mailboxes)

    Application.put_env(:pauseai_ca, :outreach_mailboxes, [
      %{
        id: "outreach_en",
        name: "Synthetic mailbox",
        email: "hello@example.org",
        locale: "en",
        owner_id: admin.id,
        enabled?: false,
        verified?: false
      }
    ])

    on_exit(fn -> Application.put_env(:pauseai_ca, :outreach_mailboxes, old) end)
    %{admin: admin, scope: Accounts.Scope.for_user(admin), person: person, address: address}
  end

  test "preview, confirm, open and reload one historical interaction linked to original participants",
       c do
    conn = log_in_user(c.conn, c.admin)
    {:ok, view, _} = live(conn, "/manage/mail/inbox?locale=en")

    refute has_element?(
             view,
             "#outreach-workspace > .management-controls > a",
             "Import an existing email"
           )

    assert has_element?(
             view,
             "#mail-more a[data-navigation-item='mail.import']",
             "Import an existing email"
           )

    view |> element("#mail-more a", "Import an existing email") |> render_click()
    assert_redirect(view, "/manage/mail/import?locale=en")
    {:ok, view, _} = live(conn, "/manage/mail/import?locale=en")

    upload =
      file_input(view, "#email-import-form", :email, [
        %{name: "march.eml", content: email(), type: "message/rfc822"}
      ])

    assert render_upload(upload, "march.eml")

    view
    |> form("#email-import-form",
      import: %{mailbox_ref: "outreach_en", context: "Montréal march"}
    )
    |> render_submit()

    assert has_element?(view, "#email-import-matches", "Alice Example")
    assert has_element?(view, "#email-import-matches", "No matching contact")
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 0
    render_submit(view, "confirm", %{"confirmation" => %{"reviewed" => "false"}})
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 0
    view |> form("#email-import-confirm", confirmation: %{reviewed: "true"}) |> render_submit()
    assert has_element?(view, "#email-import-result", "Email recorded.")
    [message] = Repo.all(PhoenixCRM.Message)
    assert message.envelope["from"] == "jeremy@example.org"
    assert message.source["context"] == "Montréal march"
    assert Base.decode64!(message.source["original_eml"]) == email()
    assert message.occurred_at == ~U[2026-11-08 15:00:00.000000Z]
    refute_receive {:email, _}
    assert Repo.aggregate(PauseAiCa.Outreach.Notification, :count) == 0
    assert Repo.aggregate(PauseAiCa.Newsletters.Delivery, :count) == 0
    assert Repo.aggregate(PhoenixCRM.Person, :count) == 1
    assert [conversation] = HistoricalImport.contact_history(c.scope, [c.address])
    assert conversation.id == message.conversation_id
    {:ok, contact, _} = live(conn, "/admin/contacts/#{c.person.id}?locale=en")
    assert has_element?(contact, "#crm-conversations a", "Montréal march")

    {:ok, conversation_view, _} =
      live(conn, "/manage/mail/conversations/#{conversation.id}?locale=en")

    assert has_element?(conversation_view, ".pmw-message-outcome", "Historical import")
    assert has_element?(conversation_view, ".pmw-message-text", "Hello Montréal!")
    download = get(conn, "/manage/mail/originals/#{conversation.id}/#{message.id}")
    assert response(download, 200) == email()
    denied = get(build_conn(), "/manage/mail/originals/#{conversation.id}/#{message.id}")
    assert denied.status in [302, 404]
  end

  test "a partial upload cannot be previewed and completes without losing the file", c do
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/manage/mail/import?locale=en")
    assert has_element?(view, "#email-import-form button[disabled]", "Preview import")

    file =
      file_input(view, "#email-import-form", :email, [
        %{name: "march.eml", content: email(), type: "message/rfc822"}
      ])

    render_upload(file, "march.eml", 40)

    render_submit(view, "preview", %{
      "import" => %{"source_kind" => "file", "mailbox_ref" => "outreach_en"}
    })

    assert has_element?(view, "[role=alert]", "still uploading")
    refute has_element?(view, "#email-import-preview")
    render_upload(file, "march.eml", 60)
    refute has_element?(view, "#email-import-form button[disabled]", "Preview import")
    view |> form("#email-import-form") |> render_submit()
    assert has_element?(view, "#email-import-preview")
  end

  test "repeat import reuses the message, conflicting Message-ID fails and revoked authority is enforced",
       c do
    {:ok, preview} = HistoricalImport.preview(c.scope, "outreach_en", email())

    assert {:ok, %{duplicate?: false, message: first}} =
             HistoricalImport.confirm(
               c.scope,
               "outreach_en",
               email(),
               preview.match_fingerprint,
               "Montréal"
             )

    assert {:ok, %{duplicate?: true, message: second}} =
             HistoricalImport.confirm(
               c.scope,
               "outreach_en",
               email(),
               preview.match_fingerprint,
               "Montréal"
             )

    assert first.id == second.id

    assert {:error, :identity_conflict} =
             HistoricalImport.confirm(
               c.scope,
               "outreach_en",
               email() <> "changed",
               preview.match_fingerprint,
               "Montréal"
             )

    c.admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

    assert {:error, :unauthorized} =
             HistoricalImport.confirm(
               c.scope,
               "outreach_en",
               email(),
               preview.match_fingerprint,
               "Montréal"
             )
  end

  test "cancelling a replacement file clears the previous preview bytes", c do
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/manage/mail/import?locale=en")

    original =
      file_input(view, "#email-import-form", :email, [
        %{name: "original.eml", content: email(), type: "message/rfc822"}
      ])

    render_upload(original, "original.eml")

    view
    |> form("#email-import-form", import: %{mailbox_ref: "outreach_en", context: ""})
    |> render_submit()

    assert has_element?(view, "#email-import-preview")

    replacement =
      file_input(view, "#email-import-form", :email, [
        %{name: "replacement.eml", content: email("replacement"), type: "message/rfc822"}
      ])

    render_upload(replacement, "replacement.eml")
    view |> element("button[phx-click=cancel-upload]") |> render_click()

    view
    |> form("#email-import-form", import: %{mailbox_ref: "outreach_en", context: ""})
    |> render_submit()

    refute has_element?(view, "#email-import-preview")
    assert has_element?(view, "[role=alert]", "Provide complete original message source")
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 0
  end

  test "paste and original-source text files share preview, confirmation and newline-safe duplicate detection",
       c do
    conn = log_in_user(c.conn, c.admin)
    {:ok, view, _} = live(conn, "/manage/mail/import?locale=en")
    assert has_element?(view, "#email-source-help", "Download message")

    assert has_element?(
             view,
             "#email-source-help a[href='https://support.google.com/mail/answer/9261412?hl=en']"
           )

    view |> form("#email-import-form", import: %{source_kind: "paste"}) |> render_change()
    source = String.replace(email(), "\r\n", "\n")

    view
    |> form("#email-import-form",
      import: %{
        source_kind: "paste",
        original_source: source,
        mailbox_ref: "outreach_en",
        context: "Montréal"
      }
    )
    |> render_submit()

    assert has_element?(view, "#email-import-preview", "Montréal march")
    view |> form("#email-import-confirm", confirmation: %{reviewed: "true"}) |> render_submit()
    assert has_element?(view, "#email-import-result", "Email recorded.")
    {:ok, next, _} = live(conn, "/manage/mail/import?locale=en")

    upload =
      file_input(next, "#email-import-form", :email, [
        %{name: "original.txt", content: email(), type: "text/plain"}
      ])

    render_upload(upload, "original.txt")

    next
    |> form("#email-import-form", import: %{mailbox_ref: "outreach_en", context: "Montréal"})
    |> render_submit()

    next |> form("#email-import-confirm", confirmation: %{reviewed: "true"}) |> render_submit()
    assert has_element?(next, "#email-import-result", "Already recorded.")
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 1
    [message] = Repo.all(PhoenixCRM.Message)
    assert Base.decode64!(message.source["original_eml"]) == source
    assert Repo.aggregate(PauseAiCa.Outreach.Notification, :count) == 0
  end

  test "switching source modes clears the previous upload and rejects a plain transcript", c do
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/manage/mail/import?locale=en")

    original =
      file_input(view, "#email-import-form", :email, [
        %{name: "original.eml", content: email(), type: "message/rfc822"}
      ])

    render_upload(original, "original.eml")
    view |> form("#email-import-form", import: %{source_kind: "paste"}) |> render_change()

    view
    |> form("#email-import-form",
      import: %{source_kind: "paste", original_source: "Just the email body"}
    )
    |> render_submit()

    assert has_element?(view, "[role=alert]", "Provide complete original message source")
    refute has_element?(view, "#email-import-preview")
    view |> form("#email-import-form", import: %{source_kind: "file"}) |> render_change()
    refute has_element?(view, "button[phx-click=cancel-upload]")
    view |> form("#email-import-form") |> render_submit()
    refute has_element?(view, "#email-import-preview")
    assert Repo.aggregate(PhoenixCRM.Message, :count) == 0
  end
end
