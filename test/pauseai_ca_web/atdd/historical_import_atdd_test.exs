if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.HistoricalImportTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.Repo

    @moduletag :atdd
    test "a superadmin imports a sent message from Inbox More and finds it on the recipient", c do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      recipient = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic recipient"})
      Repo.insert!(%PhoenixCRM.Address{email: "recipient@example.org", person_id: recipient.id})
      {token, _} = generate_user_magic_link_token(admin)
      boxes = Application.get_env(:pauseai_ca, :outreach_mailboxes, [])

      Application.put_env(:pauseai_ca, :outreach_mailboxes, [
        %{id: "outreach_demo", email: "archive@example.org", name: "Demo archive", locale: "en"}
      ])

      on_exit(fn -> Application.put_env(:pauseai_ca, :outreach_mailboxes, boxes) end)

      c.conn
      |> visit("/users/log-in/#{token}?locale=en")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
      |> visit("/manage/mail/inbox?locale=en")
      |> click("#mail-more > summary")
      |> screenshot("historical-more.png")
      |> click_link("Import an existing email")
      |> assert_has("#email-import-form")
      |> upload("Original email (.eml or .txt, up to 5 MB)", "test/fixtures/march-rehearsal.eml")
      |> click_button("Preview import")
      |> assert_has("#email-import-matches", text: "Synthetic recipient")
      |> screenshot("historical-preview.png")
      |> check("I reviewed the original message, recipient matches and mailbox access.")
      |> click_button("Confirm import")
      |> assert_has("#email-import-result", text: "Email recorded.")
      |> visit("/admin/contacts/#{recipient.id}?locale=en")
      |> assert_has("#crm-conversations", text: "March rehearsal")
      |> screenshot("historical-contact.png")
    end
  end
end
