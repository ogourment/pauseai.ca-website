defmodule PauseAiCa.OutreachAttachmentsTest do
  use PauseAiCa.DataCase, async: false
  alias PauseAiCa.{Outreach, OutreachAttachments}
  import PauseAiCa.AccountsFixtures

  setup do
    keys = [
      :outreach_mailboxes,
      :outreach_attachment_dir,
      :outreach_brevo_req_options,
      :brevo_api_key
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:pauseai_ca, &1)})
    directory = Path.join(System.tmp_dir!(), "outreach-blobs-" <> Ecto.UUID.generate())
    Application.put_env(:pauseai_ca, :outreach_attachment_dir, directory)
    Application.put_env(:pauseai_ca, :brevo_api_key, "SyntheticOnly")
    Application.put_env(:pauseai_ca, :outreach_brevo_req_options, plug: {Req.Test, __MODULE__})

    Application.put_env(:pauseai_ca, :outreach_mailboxes, [
      %{
        id: "outreach_en",
        name: "PauseAI Canada",
        email: "hello@pauseai.ca",
        locale: "en",
        owner_id: nil,
        receiving_addresses: ["hello@reply.pauseai.ca"],
        enabled?: true,
        verified?: true
      }
    ])

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> Application.put_env(:pauseai_ca, key, value) end)
      File.rm_rf(directory)
    end)

    :ok
  end

  test "an incoming attachment is private, durable and only downloadable by a current email admin" do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.resp(conn, 200, "private-file") end)
    {:ok, receipt} = Outreach.receive(payload())
    assert :ok = OutreachAttachments.ensure(receipt)
    assert {:ok, %{messages: [message]}} = Outreach.process_receipt(receipt.id)

    admin =
      user_fixture()
      |> then(fn u ->
        {:ok, u} = PauseAiCa.Repo.update(Ecto.Changeset.change(u, superadmin: true))
        u
      end)

    scope = PauseAiCa.Accounts.Scope.for_user(admin)
    assert {:ok, file} = OutreachAttachments.download(scope, receipt.id, 0, 0)
    assert File.read!(file.path) == "private-file"
    assert file.filename == "outline.pdf"
    decorated = OutreachAttachments.decorate(message)
    assert hd(decorated.attachments)["download_path"] =~ "/manage/mail/attachments/"
    refute inspect(decorated.attachments) =~ "PrivateDownloadToken"
    {:ok, _} = Repo.update(Ecto.Changeset.change(admin, superadmin: false))
    assert {:error, :not_found} = OutreachAttachments.download(scope, receipt.id, 0, 0)
  end

  test "a delegated manager downloads only its mailbox and immediately loses access on revoke" do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.resp(conn, 200, "private-file") end)
    {:ok, receipt} = Outreach.receive(payload())
    assert :ok = OutreachAttachments.ensure(receipt)
    assert {:ok, _} = Outreach.process_receipt(receipt.id)
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    manager = user_fixture() |> change(superadmin: false) |> Repo.update!()
    group = Repo.insert!(%PauseAiCa.Volunteers.Group{name: "Synthetic attachment managers"})
    Repo.insert!(%PauseAiCa.Volunteers.Manager{group_id: group.id, user_id: manager.id})
    scope = PauseAiCa.Accounts.Scope.for_user(manager)
    admin_scope = PauseAiCa.Accounts.Scope.for_user(admin)
    assert {:error, :not_found} = OutreachAttachments.download(scope, receipt.id, 0, 0)
    assert {:ok, _} = Outreach.grant_mailbox(admin_scope, "outreach_en", manager.id, 0)
    assert {:ok, file} = OutreachAttachments.download(scope, receipt.id, 0, 0)
    assert File.read!(file.path) == "private-file"
    assert Bitwise.band(File.stat!(file.path).mode, 0o777) == 0o600
    assert {:ok, _} = Outreach.revoke_mailbox(admin_scope, "outreach_en", manager.id, 1)
    assert {:error, :not_found} = OutreachAttachments.download(scope, receipt.id, 0, 0)
  end

  test "oversized provider content never becomes a downloadable blob" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.resp(conn, 200, String.duplicate("x", 10_485_761))
    end)

    {:ok, receipt} = Outreach.receive(payload())

    assert %{receipts: [{:error, :attachment_too_large}]} =
             PauseAiCa.OutreachProvider.process_once()

    [message] = Repo.all(PhoenixCRM.Message)
    assert message.body_text == "Here is the outline."
    pending = Repo.get!(PauseAiCa.Outreach.Receipt, receipt.id)
    assert pending.files_pending
    assert pending.processed_at
    assert pending.attempts == 1
    refute hd(OutreachAttachments.decorate(message).attachments)["download_path"]
  end

  defp payload do
    %{
      "items" => [
        %{
          "Uuid" => [Ecto.UUID.generate()],
          "MessageId" => "<attachment@example.org>",
          "From" => %{"Address" => "partner@example.org", "Name" => "Synthetic partner"},
          "To" => [%{"Address" => "hello@pauseai.ca"}],
          "Recipients" => ["hello@reply.pauseai.ca"],
          "Subject" => "Outline",
          "SentAtDate" => "Sat, 31 Oct 2026 10:00:00 +0000",
          "RawTextBody" => "Here is the outline.",
          "Attachments" => [
            %{
              "Name" => "outline.pdf",
              "ContentType" => "application/pdf",
              "ContentLength" => 12,
              "DownloadToken" => "PrivateDownloadToken"
            }
          ]
        }
      ]
    }
  end
end
