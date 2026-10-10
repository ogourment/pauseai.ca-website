if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.NewslettersTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Newsletters, Repo}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "PA-NEWS-01-#{locale}",
                    title: "PA-NEWS-01 · signup, consent, draft and withdrawal · #{language}",
                    tags: ["newsletter", "mail", "superadmin"],
                    roles: ["Reader", "Superadmin"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!(
        "PA-NEWS-01 · confirmed newsletter consent and authoring",
        @scenarios,
        %{browser: "Chromium", viewport: "Desktop and phone"}
      )

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      previous = Application.get_env(:swoosh, :shared_test_process)
      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.put_env(:swoosh, :shared_test_process, previous) end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "PA-NEWS-01 human journey #{locale}", c do
        journey(c, unquote(locale), unquote(width), unquote(height))
      end
    end

    defp journey(c, locale, width, height) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      admin =
        user_fixture(%{email: "news-admin-#{locale}@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      other = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      ordinary = user_fixture()
      scope = Accounts.Scope.for_user(admin)

      {:ok, _} =
        Newsletters.observe_legacy(scope, "legacy-#{locale}@example.org", %{
          "source" => "synthetic legacy evidence"
        })

      original_options = Application.fetch_env!(:pauseai_ca, :brevo_req_options)
      pid = self()

      Application.put_env(:pauseai_ca, :brevo_req_options,
        plug: fn conn ->
          send(pid, {:newsletter_provider, conn.method})
          Plug.Conn.send_resp(conn, 503, "unavailable")
        end
      )

      on_exit(fn -> Application.put_env(:pauseai_ca, :brevo_req_options, original_options) end)
      flush_emails()
      alias_email = "linked-#{locale}@example.org"
      person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic linked subscriber"})

      for address <- ["reader-#{locale}@example.org", alias_email],
          do: Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: address})

      {:ok, linked_request} =
        Newsletters.request_signup(alias_email, %{
          consent: true,
          locale: locale,
          region: "Montréal"
        })

      {:ok, _} = Newsletters.confirm(linked_request.confirmation_token)
      baseline = unrelated_counts()
      email = "reader-#{locale}@example.org"
      path = if locale == "fr", do: "/fr/comprendre", else: "/en/learn"

      reader =
        c.conn
        |> visit(path)
        |> assert_has("[data-phx-main].phx-connected")
        |> fill_in(tr(locale, "Name (optional)"), with: "Camille Synthetic")
        |> fill_in(tr(locale, "Your email"), with: email)
        |> fill_in(tr(locale, "Postal area · FSA (optional)"), with: "h2x")
        |> check(
          "#subscribe-consent",
          tr(
            locale,
            "I agree to receive emails from PauseAI Canada. We do not sell your address."
          ),
          exact: false
        )
        |> click("#subscribe")
        |> assert_has("#subscribe-success")
        |> capture(
          locale,
          "Submit explicit newsletter signup",
          "Pending consent, confirmation sent to isolated test mailbox"
        )

      pending = Repo.get_by!(Newsletters.Subscription, email: email)
      assert pending.state == "pending"
      assert pending.name == "Camille Synthetic"
      assert pending.fsa == "H2X"
      refute Newsletters.eligible?(email)
      assert baseline == unrelated_counts()
      assert_receive {:email, delivered}, 8_000
      assert delivered.to == [{"", email}]
      assert delivered.cc == [] and delivered.bcc == []

      [_, confirmation] =
        Regex.run(~r{href="(https?://[^\"]+/newsletters/confirm[^\"]+)"}, delivered.html_body)

      confirmation = String.replace(confirmation, "&amp;", "&")
      {:ok, withdrawal} = Newsletters.issue_withdrawal_token(scope, pending.id)

      admin_browser =
        new_device(c, width, height)
        |> sign_in(admin)
        |> visit("/manage/mail?locale=#{locale}")
        |> click_link(tr(locale, "Newsletter lists"))
        |> assert_has("#newsletter-#{pending.id}", text: tr(locale, "Awaiting confirmation"))
        |> capture(
          locale,
          "Open Emails and newsletter audience",
          "Pending and historical membership excluded"
        )

      admin_browser =
        admin_browser
        |> fill_in(tr(locale, "Find email or city"), with: "reader-")
        |> click_button(tr(locale, "Find"))
        |> visit("/manage/mail/newsletters?locale=#{locale}&q=reader-&per=10&region=")
        |> assert_has("#newsletter-#{pending.id}")
        |> refute_has("#newsletter-audience", text: "legacy-#{locale}")
        |> capture(
          locale,
          "Filter and reload audience",
          "Query survives reload without granting legacy consent"
        )

      denied =
        new_device(c, width, height)
        |> sign_in(ordinary)
        |> visit("/manage/mail/newsletters?locale=#{locale}")
        |> refute_has("#newsletter-audience")

      _ = denied

      reader =
        reader
        |> visit(confirmation)
        |> assert_has("#newsletter-confirm-action")
        |> capture(
          locale,
          "Open actual confirmation email link",
          "GET leaves pending consent unchanged"
        )

      refute Newsletters.eligible?(email)

      reader =
        reader
        |> click("#newsletter-confirm-action")
        |> assert_has("#newsletter-result")
        |> capture(
          locale,
          "Explicitly confirm signup",
          "POST grants eligibility without creating an account"
        )

      assert Newsletters.eligible?(email)
      reader |> visit(confirmation) |> assert_has("#newsletter-invalid")

      admin_browser =
        admin_browser
        |> visit("/manage/mail?locale=#{locale}")
        |> click_button(tr(locale, "Compose"))
        |> assert_has("#newsletter-draft-form")
        |> fill_in(tr(locale, "Subject"), with: "Synthetic press release #{locale}")
        |> fill_in(tr(locale, "Message · Markdown"),
          with: "## Montréal\n\nSynthetic press release review."
        )
        |> select(tr(locale, "Audience geography"), option: "Montréal", exact: false)
        |> click_button(tr(locale, "Save"))
        |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)
        |> capture(
          locale,
          "Compose and save newsletter draft",
          "Subject, source and audience geography persisted; no delivery"
        )

      {:ok, [draft]} = Newsletters.Drafts.list(scope)
      draft_path = "/manage/mail/drafts/#{draft.id}?locale=#{locale}"

      admin_browser =
        admin_browser
        |> visit(draft_path)
        |> assert_has("input[value='Synthetic press release #{locale}']")
        |> click_button(tr(locale, "Archive"))
        |> refute_has("#newsletter-draft-form")
        |> click_button(tr(locale, "Restore"))
        |> assert_has("#newsletter-draft-form")
        |> capture(
          locale,
          "Reload, archive and restore",
          "Draft is durable and archive reversible"
        )

      new_device(c, width, height)
      |> sign_in(other)
      |> visit(draft_path)
      |> refute_has("#newsletter-draft")

      withdrawal_path = "/newsletters/withdraw?token=#{withdrawal}"
      reader = reader |> visit(withdrawal_path) |> assert_has("#newsletter-confirm-action")
      assert Newsletters.eligible?(email)

      reader =
        reader
        |> click("#newsletter-confirm-action")
        |> assert_has("#newsletter-result")
        |> visit(withdrawal_path)
        |> click("#newsletter-confirm-action")
        |> assert_has("#newsletter-result")
        |> capture(
          locale,
          "Unsubscribe and reload/repeat",
          "Withdrawal is durable, idempotent and independent of Brevo"
        )

      refute Newsletters.eligible?(email)
      refute Newsletters.eligible?(alias_email)
      reader |> visit(confirmation) |> assert_has("#newsletter-invalid")

      admin_browser =
        admin_browser
        |> visit("/manage/mail/newsletters?locale=#{locale}")
        |> assert_has("#newsletter-#{pending.id}", text: tr(locale, "Withdrawn"))
        |> click_button("#newsletter-#{pending.id}", tr(locale, "Refresh Brevo status"))
        |> assert_has("#newsletter-error")
        |> capture(
          locale,
          "Reload withdrawn audience and fail provider refresh",
          "Inline provider failure leaves local withdrawal and draft unchanged"
        )

      refute Newsletters.eligible?(email)
      assert {:ok, saved} = Newsletters.Drafts.get(scope, draft.id)
      assert saved.source == "## Montréal\n\nSynthetic press release review."
      {:ok, _renewal} = Newsletters.request_signup(email, %{consent: true, locale: locale})
      refute Newsletters.eligible?(email)

      reader
      |> visit(withdrawal_path)
      |> click("#newsletter-confirm-action")
      |> assert_has("#newsletter-result")

      admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
      admin_browser |> visit(draft_path) |> refute_has("#newsletter-draft")
      assert baseline == unrelated_counts()
      refute_receive {:email, _}
      refute_receive {:newsletter_provider, "POST"}
      refute_receive {:newsletter_provider, "PUT"}
      refute_receive {:newsletter_provider, "DELETE"}

      scenario =
        Enum.find(@scenarios, &(&1.language == if(locale == "fr", do: "French", else: "English")))

      AtddEvidence.mark_scenario_success!(scenario)
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp new_device(c, width, height),
      do:
        PhoenixTest.Playwright.Case.new_session(
          PhoenixTest.Playwright.Config.validate!(
            browser_context_opts: [viewport: %{width: width, height: height}]
          ),
          c
        )

    defp sign_in(browser, user) do
      {token, _} = generate_user_magic_link_token(user)

      browser
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp unrelated_counts,
      do:
        Map.new(
          [
            Accounts.User,
            PauseAiCa.Volunteers.Invitation,
            PauseAiCa.ContactMigration.Contact,
            PhoenixCRM.Person,
            PauseAiCa.Mail.Batch,
            PauseAiCa.Mail.Draft
          ],
          &{&1, Repo.aggregate(&1, :count)}
        )

    defp flush_emails do
      receive do
        {:email, _} -> flush_emails()
      after
        0 -> :ok
      end
    end

    defp capture(browser, locale, trigger, outcome) do
      step = Process.get({:newsletter_step, locale}, 0) + 1
      Process.put({:newsletter_step, locale}, step)
      filename = "PA-NEWS-01-#{locale}-#{String.pad_leading(to_string(step), 2, "0")}.png"
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(filename, trigger, outcome, %{
        "scenario_id" => "PA-NEWS-01-#{locale}",
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser)),
        "step" => step,
        "external_systems" => "Synthetic local DB and captured Swoosh mail; no live Brevo writes"
      })

      browser
    end
  end
end
