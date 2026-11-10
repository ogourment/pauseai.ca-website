if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.NewsletterListComposerTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Newsletters, Repo}
    alias PauseAiCaWeb.AtddEvidence

    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "MAIL-LIST-COMPOSE-01-#{locale}",
                     title: "Whole-list audience and reachable message editor · #{language}",
                     roles: ["Superadmin"],
                     language: language,
                     device: device,
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!("MAIL-LIST-COMPOSE-01 · Ottawa list composer", @scenarios, %{
        browser: "Chromium",
        viewport: "English desktop and French phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "MAIL-LIST-COMPOSE-01 opens an Ottawa list and edits its private message #{locale}",
           c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      scope = Accounts.Scope.for_user(admin)
      {:ok, list} = Newsletters.Lists.save(scope, nil, %{"name" => "Ottawa", "city" => "Ottawa"})

      for number <- 1..2 do
        Repo.insert!(%Newsletters.Subscription{
          email: "ottawa-composer-#{locale}-#{number}@example.org",
          city: "Ottawa",
          state: "confirmed",
          confirmed_at: DateTime.utc_now(),
          consent_version: "synthetic-composer-consent"
        })
      end

      {token, _} = generate_user_magic_link_token(admin)
      flush_emails()

      summary =
        tr(locale, "%{list} · %{count} eligible · %{edition}",
          list: "Ottawa",
          count: 2,
          edition: tr(locale, "Bilingual · language unknown only")
        )

      browser =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/manage/mail/newsletters?locale=#{locale}")
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#mailing-list-#{list.id}", text: "Ottawa")
        |> click_button("#mailing-list-#{list.id} button", tr(locale, "Compose"), exact: true)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#newsletter-draft-form")
        |> assert_has("#email-audience-summary", text: summary, exact: true)
        |> assert_has("#email-recipient-settings:not([open])")
        |> refute_has("#newsletter-selected-count")
        |> capture(
          locale,
          1,
          "Whole Ottawa list ready for authoring",
          "Newsletter lists",
          "Ottawa → Compose",
          "The private composer identifies Ottawa, two eligible recipients and unknown-language bilingual edition. Recipient settings are collapsed and message entry is directly reachable."
        )
        |> click_link("#email-write-message", tr(locale, "Write message"), exact: true)
        |> assert_has("#email-message input[name='draft[subject]']")

      PhoenixTest.Playwright.evaluate(browser, "location.hash", fn hash ->
        assert hash == "#email-message"
      end)

      subject = "Synthetic Ottawa invitation #{locale}"
      source = "## Synthetic Ottawa\n\nAn isolated bilingual review message."

      browser =
        browser
        |> fill_in(tr(locale, "Subject"), with: subject)
        |> assert_has("#email-message input[name='draft[subject]']", value: subject)
        |> fill_in(tr(locale, "Message · Markdown"), with: source)
        |> assert_has("#newsletter-save-status", text: tr(locale, "Unsaved changes"), exact: true)
        |> click_button("#newsletter-draft-form button", tr(locale, "Save"), exact: true)
        |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)

      assert {:ok, [draft]} = Newsletters.Drafts.list(scope)
      assert draft.owner_id == admin.id
      assert draft.subject == subject
      assert draft.source == source
      assert draft.mailing_list_id == list.id
      assert draft.recipient_mode == "list"
      assert draft.recipient_keys == []
      assert draft.edition == "unknown"

      path = "/manage/mail/drafts/#{draft.id}?locale=#{locale}"

      browser =
        browser
        |> visit(path)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#email-audience-summary", text: summary, exact: true)
        |> assert_has("#email-recipient-settings:not([open])")
        |> assert_has("#email-message input[name='draft[subject]']", value: subject)
        |> click_button("#email-choose-recipients", tr(locale, "Choose recipients"), exact: true)
        |> assert_has("#email-recipient-settings[open]")
        |> assert_has("#draft_recipient_mode:focus", value: "list")
        |> assert_has("#whole-list-audience", text: tr(locale, "Eligible") <> ": 2")
        |> capture(
          locale,
          2,
          "Saved message and explicit audience controls",
          "Saved private Ottawa composer",
          "Reload saved draft → Choose recipients",
          "The saved subject and body persist. Choose recipients opens the existing audience source selector while preserving the whole Ottawa list and two eligible recipients."
        )

      assert Repo.aggregate(Newsletters.Batch, :count) == 0
      assert Repo.aggregate(Newsletters.Delivery, :count) == 0
      refute_received {:email, _}

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "MAIL-LIST-COMPOSE-01-#{locale}"))
      )

      browser
    end

    defp capture(browser, locale, step, title, preceding, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:list_composer_url, &1)
      )

      url = AtddEvidence.safe_url(Process.get(:list_composer_url))
      IO.puts("Capture URL: #{url}")
      filename = "MAIL-LIST-COMPOSE-01-#{locale}-#{step}.png"
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(filename, title, outcome, %{
        "scenario_id" => "MAIL-LIST-COMPOSE-01-#{locale}",
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "step" => step,
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser)),
        "external_systems" =>
          "Synthetic local newsletter fixtures and private drafts only. No sending or provider calls."
      })

      browser
    end

    defp flush_emails do
      receive do
        {:email, _} -> flush_emails()
      after
        0 -> :ok
      end
    end

    defp tr(locale, text, bindings \\ []),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text, bindings)
        end)
  end
end
