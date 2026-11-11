if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.OutreachDelegationTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Outreach, Repo, Volunteers}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "OUTREACH-DELEGATE-01-#{locale}",
                     title:
                       "OUTREACH-DELEGATE-01 · Delegated mailbox and fresh revocation · #{language}",
                     tags: ["mail", "delegation", "authorization"],
                     roles: ["Superadmin", "Group manager"],
                     language: language,
                     device: device,
                     surface: "LiveView",
                     host_os: "Linux",
                     theme: "light",
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!("OUTREACH-DELEGATE-01 · Manage mailbox access", @scenarios, %{
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

      admin =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true, name: "Synthetic Admin")
        |> Repo.update!()

      manager =
        user_fixture(%{email: "delegation-review@example.org"})
        |> Ecto.Changeset.change(name: "Synthetic Manager")
        |> Repo.update!()

      scope = Accounts.Scope.for_user(admin)
      {:ok, group} = Volunteers.create_group(scope, %{"name" => "Synthetic mailbox managers"})
      {:ok, _} = Volunteers.assign_manager(scope, group.id, manager.email)
      previous = Application.get_env(:pauseai_ca, :outreach_mailboxes)

      boxes =
        for {id, email, locale} <- [
              {"outreach_en", "hello@pauseai.ca", "en"},
              {"outreach_fr", "bonjour@pauseia.ca", "fr"}
            ],
            do: %{
              id: id,
              name: "PauseAI Canada",
              email: email,
              locale: locale,
              owner_id: admin.id,
              enabled?: true,
              verified?: true
            }

      Application.put_env(:pauseai_ca, :outreach_mailboxes, boxes)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:pauseai_ca, :outreach_mailboxes, previous),
          else: Application.delete_env(:pauseai_ca, :outreach_mailboxes)
      end)

      flush_mail()
      %{admin: admin, scope: scope, manager: manager}
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "OUTREACH-DELEGATE-01 manager mailbox #{locale}", c do
        locale = unquote(locale)
        id = "OUTREACH-DELEGATE-01-#{locale}"
        ref = "outreach_#{locale}"
        other = if locale == "en", do: "outreach_fr", else: "outreach_en"
        conversation = conversation(ref, "Synthetic delegated conversation", c.admin.id)
        conversation(other, "Unassigned mailbox conversation", c.admin.id)

        b =
          c.conn
          |> login(c.manager)
          |> visit("/manage/mail/inbox?locale=#{locale}")
          |> roots(locale)
          |> assert_has("#outreach-no-access")
          |> refute_has("#outreach-filters")
          |> capture(
            id,
            "Manager → Manage → Emails → Inbox",
            "No grant is explained explicitly; private mailbox data is absent"
          )

        b =
          switch_browser_identity(b, &login(&1, c.admin))
          |> visit("/manage/mail?locale=#{locale}")
          |> click("#mail-more > summary")
          |> click_link("[data-navigation-item='mail.access']", tr(locale, "Mailbox access"))
          |> assert_has("#mailbox-access")
          |> select(tr(locale, "Manager account"),
            option: "Synthetic Manager · #{c.manager.email}"
          )
          |> click_button(
            "#mailbox-cell-#{ref}-#{c.manager.id} button",
            tr(locale, "Grant access")
          )
          |> assert_has("#mailbox-cell-#{ref}-#{c.manager.id} button", text: tr(locale, "Revoke"))
          |> capture(
            id,
            "Superadmin → Mailbox access → choose existing manager → Grant access",
            "Only one mailbox is delegated; the other mailbox has its own action"
          )

        b =
          switch_browser_identity(b, &login(&1, c.manager))
          |> visit("/manage/mail/inbox?locale=#{locale}")
          |> roots(locale)
          |> refute_has("#outreach-no-access")
          |> click("#outreach-compose > summary")
          |> only_mailbox("select[name='outreach[mailbox_ref]']", ref)
          |> refute_has("#outreach-conversations", text: "Unassigned mailbox conversation")
          |> capture(
            id,
            "Granted manager → Manage → Emails → Inbox → Compose outreach email",
            "Inbox and From expose only the granted mailbox; no admin-only settings or recovery controls"
          )

        b =
          b
          |> click_link(nil, "Synthetic delegated conversation")
          |> assert_path("/manage/mail/conversations/#{conversation.id}")
          |> click_button(tr(locale, "Reply"))
          |> assert_has("#newsletter-draft-form")
          |> roots(locale)
          |> only_mailbox("#outreach-addressing select", ref)
          |> capture(
            id,
            "Inbox → conversation → Reply",
            "The same shared editor retains the actual Inbox path for the manager"
          )

        b =
          b
          |> fill_in(tr(locale, "Message · Markdown"),
            with: "Synthetic delegated reply; no external transport."
          )
          |> click_button(tr(locale, "Save"))
          |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)
          |> check(
            tr(locale, "I reviewed these contacts’ eligibility for this invitation or message.")
          )
          |> click_button(tr(locale, "Review & send"))
          |> assert_has("#newsletter-batch-review")
          |> roots(locale)
          |> capture(
            id,
            "Manager → Save → Review & send",
            "A prepared reply exists under the manager's account; no send or approval occurs"
          )

        {:ok, [draft]} = PauseAiCa.Newsletters.Drafts.list(Accounts.Scope.for_user(c.manager))
        assert draft.owner_id == c.manager.id and draft.conversation_id == conversation.id
        assert {:ok, _} = Outreach.revoke_mailbox(c.scope, ref, c.manager.id, 1)

        b =
          b
          |> click_button(tr(locale, "Send now"))
          |> assert_has("#newsletter-draft-error",
            text:
              tr(
                locale,
                "Access changed. Review your mailbox access and prepare this draft again before sending."
              )
          )
          |> capture(
            id,
            "Superadmin revokes grant → manager attempts prepared Send now",
            "Fresh permission denies delivery and preserves the saved draft for a new review"
          )

        assert Repo.get!(PauseAiCa.Newsletters.Draft, draft.id).source ==
                 "Synthetic delegated reply; no external transport."

        assert Enum.all?(Repo.all(PauseAiCa.Newsletters.Delivery), &is_nil(&1.attempted_at))
        refute_receive {:email, _}
        _ = b
        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      end
    end

    defp conversation(ref, subject, actor_id) do
      conversation =
        Repo.insert!(%PhoenixCRM.Conversation{
          mailbox_ref: ref,
          subject: subject,
          participants: ["synthetic-partner@example.org"],
          actor_id: actor_id
        })

      Repo.insert!(%PhoenixCRM.Message{
        conversation_id: conversation.id,
        mailbox_ref: ref,
        direction: :inbound,
        idempotency_key: "delegation-#{conversation.id}",
        rfc_message_id: "<#{conversation.id}@example.org>",
        actor_id: actor_id,
        outcome: :received,
        envelope: %{
          "from" => "synthetic-partner@example.org",
          "to" => ["hello@pauseai.ca"],
          "subject" => subject
        },
        body_text: "Synthetic local navigation proof."
      })

      conversation
    end

    defp login(b, actor) do
      {token, _} = generate_user_magic_link_token(actor)

      b
      |> visit("/users/log-in/#{token}?locale=en")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp only_mailbox(b, selector, ref) do
      b = assert_has(b, selector)

      evaluate(
        b,
        "[...document.querySelector(" <> Jason.encode!(selector) <> ").options].map(x=>x.value)",
        &assert(&1 == [ref])
      )

      b
    end

    defp roots(b, locale) do
      b = assert_has(b, "#journey-breadcrumbs li")

      evaluate(
        b,
        "[...document.querySelectorAll('#journey-breadcrumbs li')].map(x=>x.textContent)",
        fn labels ->
          assert labels != []
          refute tr(locale, "My account") in labels
          refute tr(locale, "Admin") in labels
        end
      )

      b
    end

    defp capture(b, id, control, outcome) do
      evaluate(b, "location.href", &Process.put(:delegation_url, AtddEvidence.safe_url(&1)))
      url = Process.get(:delegation_url)
      IO.puts("Capture URL: [#{url}](#{url}); preceding/control: #{control}")
      evaluate(b, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      step = Process.get({id, :step}, 0) + 1
      Process.put({id, :step}, step)
      name = "#{id}-#{step}.png"
      b = AtddEvidence.capture_full_page(b, name)

      AtddEvidence.record_step(name, control, outcome, %{
        "scenario_id" => id,
        "step" => step,
        "url" => url,
        "control" => control,
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(b)),
        "source" =>
          "Actual isolated local application; synthetic users/mailboxes/messages and SQL sandbox rollback. No live provider, DNS, real mail or deployed role mutation."
      })

      b
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp flush_mail do
      receive do
        {:email, _} -> flush_mail()
      after
        0 -> :ok
      end
    end
  end
end
