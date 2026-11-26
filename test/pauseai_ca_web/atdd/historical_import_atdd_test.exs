if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.HistoricalImportTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias AcceptanceHarness.Evidence
    alias PauseAiCa.Repo
    alias PauseAiCaWeb.{AtddEvidence, AtddNavigation}

    @assistant_summary "Superadmin: in Gmail on a computer open each original in Sent, then the message's More → Download message (.eml). In Manage → Emails (under Communications) → More → Import an existing email, choose Save to mailbox: this controls who may read the copy. Sender and recipients come from the original. Upload one file, Preview import, review Contact matches (unmatched addresses stay in the message), tick the review checkbox and Confirm import. Open the conversation or matched contact history. Repeat per message. Nothing is sent and no contacts or subscriptions are created."
    @moduletag :atdd
    @journeys [
      {"en", "English", "Desktop", 1280, 900},
      {"fr", "French", "Phone", 390, 844}
    ]
    @scenarios (for {locale, language, device, _, _} <- @journeys do
                  %{
                    id: "HIST-EMAIL-01-#{locale}",
                    title: "Record an existing sent email · #{language}",
                    tags: ["crm", "historical email"],
                    roles: ["Superadmin"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)
    @fixture "test/fixtures/march-rehearsal.eml"

    setup_all do
      AtddEvidence.reset!("HIST-EMAIL-01 · Historical email import", @scenarios, %{
        browser: "Chromium",
        viewport: "English desktop and French phone",
        application_version: app_version(:pauseai_ca),
        mail_workflow_version: app_version(:phoenix_mail_workflow),
        crm_version: app_version(:phoenix_crm),
        acceptance_harness_version: app_version(:acceptance_harness)
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, _, _, width, height} <- @journeys do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "HIST-EMAIL-01 imports a sent message from Emails More and finds it on the recipient (#{locale})",
           c do
        locale = unquote(locale)
        scenario = Enum.find(@scenarios, &(&1.id == "HIST-EMAIL-01-#{locale}"))
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        recipient = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic recipient"})
        Repo.insert!(%PhoenixCRM.Address{email: "recipient@example.org", person_id: recipient.id})
        {token, _} = generate_user_magic_link_token(admin)
        boxes = Application.get_env(:pauseai_ca, :outreach_mailboxes, [])

        Application.put_env(:pauseai_ca, :outreach_mailboxes, [
          %{
            id: "outreach_demo",
            email: "archive@example.org",
            name: "Demo archive",
            locale: locale
          }
        ])

        on_exit(fn -> Application.put_env(:pauseai_ca, :outreach_mailboxes, boxes) end)

        c.conn
        |> visit("/users/log-in/#{token}?locale=#{locale}")
        |> click_button(tr(locale, "Keep me logged in on this device"))
        |> assert_path("/")
        |> visit("/#{locale}")
        |> AtddNavigation.open_section("manage")
        |> assert_has("#manage-menu", text: tr(locale, "Communications"))
        |> capture(
          scenario,
          1,
          "Open Manage on the homepage",
          "Emails is available under Communications."
        )
        |> click_link("#manage-menu [data-navigation-item='pauseai.mail']", tr(locale, "Emails"),
          exact: true
        )
        |> assert_path("/manage/mail")
        |> assert_has("[data-phx-main].phx-connected")
        |> click("#mail-more > summary")
        |> assert_has("#mail-more[open]")
        |> capture(scenario, 2, "Open Emails More", "The historical import action is available.")
        |> click_link(tr(locale, "Import an existing email"))
        |> assert_has("#email-import-form",
          text:
            tr(
              locale,
              "People with access to this mailbox can read the copy. Sender and recipients come from the original email."
            )
        )
        |> assert_has("[data-phx-main].phx-connected")
        |> evaluate(
          """
          (() => {
            const mailbox = document.querySelector("#email-import-form select[name='import[mailbox_ref]']");
            return [mailbox.value, mailbox.selectedOptions[0].textContent.trim()];
          })()
          """,
          &assert(&1 == ["outreach_demo", "archive@example.org"])
        )
        |> upload(tr(locale, "Original email (.eml or .txt, up to 5 MB)"), @fixture)
        |> assert_has("#email-import-form", text: Path.basename(@fixture))
        |> click_button(tr(locale, "Preview import"))
        |> assert_has("#email-import-preview > p", text: "<organizer@example.org>")
        |> assert_has("#email-import-preview > p", text: "TO recipient@example.org")
        |> assert_has("#email-import-matches li",
          text: "recipient@example.org · Synthetic recipient"
        )
        |> assert_has("#email-import-matches li",
          text:
            "organizer@example.org · " <>
              tr(locale, "No matching contact. Address retained in the message.")
        )
        |> capture(
          scenario,
          3,
          "Preview the original email",
          "The recipient matches a CRM contact and the unmatched original sender is retained."
        )
        |> check(
          tr(locale, "I reviewed the original message, recipient matches and mailbox access.")
        )
        |> click_button(tr(locale, "Confirm import"))
        |> assert_has("#email-import-result > p",
          text: tr(locale, "Email recorded."),
          exact: true
        )
        |> capture(scenario, 4, "Confirm the import", "The email was recorded.")
        |> click_link(tr(locale, "Open conversation"))
        |> assert_has("h1", text: "March rehearsal")
        |> visit("/admin/contacts/#{recipient.id}?locale=#{locale}")
        |> assert_has("#crm-conversations", text: "March rehearsal")
        |> capture(
          scenario,
          5,
          "Open the recipient’s CRM record",
          "The saved conversation appears in contact history.",
          %{"assistant_summary" => @assistant_summary}
        )

        message =
          Repo.get_by!(PhoenixCRM.Message, rfc_message_id: "<march-rehearsal@example.org>")

        assert message.mailbox_ref == "outreach_demo"
        assert message.actor_id == admin.id
        assert message.envelope["from"] == "organizer@example.org"
        assert message.envelope["to"] == ["recipient@example.org"]
        refute Repo.get_by(PhoenixCRM.Address, email: "organizer@example.org")
        assert message.source["kind"] == "historical_import"
        assert Base.decode64!(message.source["original_eml"]) == File.read!(@fixture)

        Evidence.record_current_scenario_runtime(scenario)
        AtddEvidence.mark_scenario_success!(scenario)
      end
    end

    defp app_version(app), do: app |> Application.spec(:vsn) |> to_string()

    defp tr(locale, text) do
      Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
        Gettext.gettext(PauseAiCaWeb.Gettext, text)
      end)
    end

    defp capture(browser, scenario, step, action, outcome, extra_metadata \\ %{}) do
      filename = "#{scenario.id}-#{step}.png"
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        action,
        outcome,
        Map.merge(
          %{
            "scenario_id" => scenario.id,
            "step" => step,
            "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser)),
            "external_systems" => "Synthetic local database only"
          },
          extra_metadata
        )
      )

      browser
    end
  end
end
