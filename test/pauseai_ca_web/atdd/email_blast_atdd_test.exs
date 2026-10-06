if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.EmailBlastTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Newsletters, Repo}
    alias PauseAiCa.Newsletters.{Batches, Delivery}
    alias PauseAiCaWeb.AtddEvidence
    import Ecto.Query, only: [from: 2]
    @moduletag :atdd
    @scenarios Enum.map([{"en", "English", "Desktop"}, {"fr", "French", "Phone"}], fn {locale,
                                                                                       language,
                                                                                       device} ->
                 %{
                   id: "PA-SEND-01-#{locale}",
                   title:
                     "PA-SEND-01 · manually reviewed fourteen-contact protest blast · #{language}",
                   tags: ["mail", "newsletter", "superadmin"],
                   roles: ["Superadmin", "Recipient"],
                   language: language,
                   device: device,
                   source_file: __ENV__.file
                 }
               end)
    setup_all do
      AtddEvidence.reset!("PA-SEND-01 · manual protest press-release blast", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      old = Application.get_env(:swoosh, :shared_test_process)
      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.put_env(:swoosh, :shared_test_process, old) end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "PA-SEND-01 complete manual blast #{locale}", c do
        run_blast(c, unquote(locale))
      end
    end

    @tag browser_context_opts: [viewport: %{width: 1280, height: 900}]
    test "PA-SEND-01 control path preserves paged selections, expires approval and redirects a throttled staging batch",
         c do
      actor =
        user_fixture(%{email: "blast-controls@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      scope = Accounts.Scope.for_user(actor)

      keys =
        for n <- 1..30 do
          person =
            Repo.insert!(%PhoenixCRM.Person{
              name: "Control contact #{String.pad_leading(to_string(n), 3, "0")}"
            })

          Repo.insert!(%PhoenixCRM.Address{
            person_id: person.id,
            email: "control-#{n}@example.org"
          })

          person.id
        end

      {:ok, draft} = Newsletters.Drafts.create(scope)

      {:ok, draft} =
        Newsletters.Drafts.save(scope, draft, %{
          "subject" => "Staging control batch",
          "source" => "Synthetic approval/throttle rehearsal",
          "recipient_mode" => "contacts"
        })

      old_environment = Application.fetch_env!(:pauseai_ca, :mail_environment)
      Application.put_env(:pauseai_ca, :mail_environment, :staging)
      on_exit(fn -> Application.put_env(:pauseai_ca, :mail_environment, old_environment) end)
      flush_emails()
      {token, _} = generate_user_magic_link_token(actor)
      path = "/manage/mail/newsletters/#{draft.id}?locale=en"

      b =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit(path)
        |> click_button("Select visible available recipients")
        |> assert_has("#newsletter-selected-count", text: "25 selected")
        |> click_button("Next")
        |> check("Select control-26@example.org")
        |> assert_has("#newsletter-selected-count", text: "26 selected")
        |> click_button("Previous")
        |> click_button("Save")
        |> assert_has("#newsletter-save-status", text: "Saved")
        |> visit(path)
        |> assert_has("#newsletter-selected-count", text: "26 selected")
        |> capture(
          "controls",
          "Select across pages and reload",
          "Hidden previous-page selections persist with the visible checkboxes"
        )

      b =
        b
        |> click_button("Clear selection")
        |> assert_has("#newsletter-selected-count", text: "0 selected")
        |> click_button("Select visible available recipients")
        |> assert_has("#newsletter-selected-count", text: "25 selected")
        |> click_button("Save")
        |> check(
          "I reviewed the selected contacts' eligibility for this communication. This does not grant newsletter consent."
        )
        |> click_button("Prepare batch")
        |> click_button("Approve batch")

      [old_batch] = Repo.all(Newsletters.Batch)

      b =
        b
        |> fill_in("Subject", with: "Changed approved control batch")
        |> click_button("Save")
        |> click_button("#{old_batch.subject} · 25 · Approved")
        |> click_button("Send")
        |> assert_has("#newsletter-delivery-progress", text: "Approval expired")
        |> capture(
          "controls",
          "Edit after approval and try sending the old snapshot",
          "Approval expires before any envelope is submitted"
        )

      refute_receive {:email, _}
      assert Repo.get!(Newsletters.Batch, old_batch.id).state == "stale"

      b =
        b
        |> check(
          "I reviewed the selected contacts' eligibility for this communication. This does not grant newsletter consent."
        )
        |> click_button("Prepare batch")
        |> click_button("Approve batch")
        |> click_button("Send")
        |> assert_has("#newsletter-delivery-progress", text: "20 / 25", timeout: 30_000)
        |> assert_has("#newsletter-delivery-progress",
          text: "Waiting for hourly allowance",
          timeout: 30_000
        )
        |> capture(
          "controls",
          "Approve the changed snapshot and send the staging rehearsal",
          "Twenty envelopes go only to the authorizing admin; five remain durable pending"
        )

      for _ <- 1..20 do
        assert_receive {:email, email}, 8000
        assert email.to == [{"Staging admin", actor.email}]
        assert String.starts_with?(email.subject, "[STAGING]")
        assert email.cc == [] and email.bcc == []
      end

      refute_receive {:email, _}
      latest = Repo.all(from d in Delivery, where: d.state == "pending")
      # The stale snapshot remains entirely unsent; the active one retains exactly five pending.
      assert Enum.count(latest, &(&1.batch_id != old_batch.id)) == 5
      assert {:ok, %{personal_remaining: 0}} = Batches.quota(scope)
      assert length(keys) == 30
      _ = b

      AtddEvidence.mark_scenario_success!(%{
        id: "PA-SEND-01-controls",
        title: "PA-SEND-01 · paged selection, stale approval, staging quota",
        tags: ["mail", "newsletter", "superadmin"],
        roles: ["Superadmin"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      })
    end

    defp run_blast(c, locale) do
      actor =
        user_fixture(%{email: "blast-admin-#{locale}@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      scope = Accounts.Scope.for_user(actor)
      flush_emails()

      baseline = %{
        accounts: Repo.aggregate(Accounts.User, :count),
        invitations: Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count)
      }

      b = c.conn |> visit("/en/montreal-protest-2026-09-26/press-release")

      b
      |> evaluate(
        "document.querySelector('#protest-press-release-page').innerText",
        &Process.put(:blast_press_release, &1)
      )

      source = Process.get(:blast_press_release)
      assert source =~ "AIs are starting to do increasingly sophisticated things"

      csv =
        "Name,Email,City,Geography,Signup\n" <>
          Enum.map_join(
            1..14,
            "\n",
            &"Synthetic protest contact #{&1},blast-#{locale}-#{&1}@example.org,Montréal,Montréal,45945"
          )

      file = "tmp/PA-SEND-01-#{locale}.csv"
      File.write!(file, csv)
      {token, _} = generate_user_magic_link_token(actor)

      b =
        b
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/admin/contact-imports?locale=#{locale}")
        |> upload(tr(locale, "CSV file"), file)
        |> fill_in(tr(locale, "Source label"), with: "synthetic-press-#{locale}")
        |> click_button(tr(locale, "Preview"))
        |> assert_has("#contact-preview")

      b =
        Enum.reduce(1..14, b, fn i, b ->
          check(b, tr(locale, "Select %{email}", %{email: "blast-#{locale}-#{i}@example.org"}))
        end)

      b =
        b
        |> assert_has("#selected-count", text: tr(locale, "%{count} selected", %{count: 14}))
        |> capture(
          locale,
          "Check fourteen CSV rows individually",
          "Preview remains send/account/consent-free"
        )
        |> click_button(tr(locale, "Import selected contacts"))
        |> assert_has("#receipt-summary")
        |> capture(
          locale,
          "Import selected CSV contacts",
          "Exactly fourteen identities with preserved source dates"
        )

      assert Repo.aggregate(PauseAiCa.ContactMigration.Contact, :count) == 14
      assert Repo.aggregate(PhoenixCRM.Person, :count) == 14
      assert Repo.aggregate(Newsletters.Subscription, :count) == 0
      assert baseline == unrelated_counts()
      refute_receive {:email, _}

      b =
        b
        |> visit("/manage/mail?locale=#{locale}")
        |> click_link(tr(locale, "Newsletters"))
        |> click_button(tr(locale, "New draft"))
        |> assert_has("#newsletter-draft-form")
        |> fill_in(tr(locale, "Subject"), with: "September 26 protest press release #{locale}")
        |> fill_in(tr(locale, "Message · Markdown"), with: source)
        |> select(tr(locale, "Audience source"),
          option: tr(locale, "Contacts · manual review"),
          exact: false
        )

      b =
        Enum.reduce(1..14, b, fn i, b ->
          check(b, tr(locale, "Select %{email}", %{email: "blast-#{locale}-#{i}@example.org"}))
        end)

      b =
        b
        |> assert_has("#newsletter-selected-count",
          text: tr(locale, "%{count} selected", %{count: 14})
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"))
        |> capture(
          locale,
          "Compose actual PR and save fourteen selected contacts",
          "No subscription consent or provider submission"
        )

      {:ok, [draft]} = Newsletters.Drafts.list(scope)
      path = "/manage/mail/newsletters/#{draft.id}?locale=#{locale}"

      b =
        b
        |> visit(path)
        |> assert_has("#newsletter-selected-count",
          text: tr(locale, "%{count} selected", %{count: 14})
        )
        |> click_button(tr(locale, "Prepare batch"))
        |> assert_has("#newsletter-draft-error")
        |> capture(
          locale,
          "Reload and try preparing without review",
          "Selection persists; inline error writes no batch"
        )

      assert Repo.aggregate(Newsletters.Batch, :count) == 0

      b =
        b
        |> check(
          tr(
            locale,
            "I reviewed the selected contacts' eligibility for this communication. This does not grant newsletter consent."
          )
        )
        |> click_button(tr(locale, "Prepare batch"))
        |> assert_has("#newsletter-batch-review")
        |> refute_has("button[phx-click=send-batch]")
        |> capture(
          locale,
          "Prepare frozen reviewed snapshot",
          "Sender, version, fourteen recipients and authorizer are visible"
        )

      [batch] = Repo.all(Newsletters.Batch)
      assert {:ok, same} = Batches.prepare(scope, draft, "contacts", draft.recipient_keys, true)
      assert same.id == batch.id

      b =
        b
        |> click_button(tr(locale, "Approve batch"))
        |> assert_has("button[phx-click=send-batch]")
        |> capture(
          locale,
          "Approve exact snapshot",
          "Fresh superadmin approval required before submission"
        )
        |> click_button(tr(locale, "Send"))
        |> assert_has("#newsletter-delivery-progress", text: "14 / 14", timeout: 30_000)
        |> assert_has("#newsletter-delivery-progress",
          text: tr(locale, "Completed"),
          timeout: 30_000
        )
        |> capture(
          locale,
          "Send fourteen reviewed messages",
          "Fourteen durable local acceptance receipts, no cc/bcc"
        )

      messages =
        for _ <- 1..14 do
          assert_receive {:email, email}, 8000
          assert email.cc == [] and email.bcc == []
          assert email.html_body =~ "Manage my subscription"
          assert email.text_body =~ "AIs are starting to do increasingly sophisticated things"
          email
        end

      assert length(Enum.uniq_by(messages, & &1.to)) == 14

      assert Enum.all?(
               Repo.all(Delivery),
               &(&1.state == "accepted" and &1.authorizing_admin_id == actor.id)
             )

      assert Enum.all?(
               Repo.all(Newsletters.Subscription),
               &(&1.state == "outreach_only" and is_nil(&1.confirmed_at))
             )

      b =
        b
        |> visit(path)
        |> click_button("#{batch.subject} · 14 · #{tr(locale, "Completed")}")
        |> assert_has("#newsletter-delivery-progress", text: "14 / 14")
        |> capture(
          locale,
          "Reload completed receipt",
          "No duplicate sending and no lost selection"
        )

      assert {:ok, :not_approved} = Batches.dispatch(scope, batch.id)
      refute_receive {:email, _}

      [_, url] =
        Regex.run(~r{href="(https?://[^\"]+/newsletters/withdraw[^\"]+)"}, hd(messages).html_body)

      url = String.replace(url, "&amp;", "&")
      # Use an independent signed-out browser identity for the actual personal preference link.
      config =
        PhoenixTest.Playwright.Config.validate!(
          browser_context_opts: [viewport: %{width: 390, height: 844}]
        )

      reader =
        PhoenixTest.Playwright.Case.new_session(config, c)
        |> visit(url)
        |> assert_has("#newsletter-confirm-action")

      [{_, recipient}] = hd(messages).to
      assert Newsletters.outreach_eligible?(recipient)

      reader =
        reader
        |> click("#newsletter-confirm-action")
        |> assert_has("#newsletter-result")
        |> capture(
          locale,
          "Recipient explicitly opts out",
          "GET unchanged; POST blocks future outreach without accounts"
        )

      refute Newsletters.outreach_eligible?(recipient)
      assert baseline == unrelated_counts()
      actor |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
      b |> visit(path) |> refute_has("#newsletter-draft")
      refute_receive {:email, _}
      _ = reader

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "PA-SEND-01-#{locale}"))
      )
    end

    defp unrelated_counts,
      do: %{
        accounts: Repo.aggregate(Accounts.User, :count),
        invitations: Repo.aggregate(PauseAiCa.Volunteers.Invitation, :count)
      }

    defp tr(locale, text, bindings \\ %{}),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text, bindings)
        end)

    defp flush_emails do
      receive do
        {:email, _} -> flush_emails()
      after
        0 -> :ok
      end
    end

    defp capture(b, locale, trigger, outcome) do
      step = Process.get({:blast_step, locale}, 0) + 1
      Process.put({:blast_step, locale}, step)
      name = "PA-SEND-01-#{locale}-#{String.pad_leading(to_string(step), 2, "0")}.png"
      b = AtddEvidence.capture_full_page(b, name)

      AtddEvidence.record_step(name, trigger, outcome, %{
        "scenario_id" => "PA-SEND-01-#{locale}",
        "step" => step,
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(b)),
        "external_systems" => "Synthetic captured mail only; no live Brevo transport"
      })

      b
    end
  end
end
