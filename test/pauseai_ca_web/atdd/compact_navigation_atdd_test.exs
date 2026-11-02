if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.CompactNavigationTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, CRM, Outreach, Repo, Volunteers}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    # Local capture announcement may pause before a newly resolved editor URL.
    # Browser assertions retain the normal timeout; CI never enables this gate.
    @moduletag timeout: if(System.get_env("NAV_CAPTURE_GATE_DIR"), do: 180_000, else: 60_000)
    @flows [{"en", 1280, 900}, {"fr", 390, 844}]
    @responsive [{"en", 390, 844}, {"en", 768, 900}, {"fr", 768, 900}, {"fr", 1280, 900}]
    @scenarios for {locale, width, _} <- @flows ++ @responsive,
                   do: %{
                     id: "OUTREACH-NAV-01-#{locale}-#{width}",
                     title: "Compact section menus and actual journeys · #{locale} · #{width}px",
                     language: if(locale == "fr", do: "French", else: "English"),
                     device: if(width < 600, do: "Phone", else: "Desktop/tablet"),
                     roles: ["Account", "Group manager", "Superadmin"],
                     tags: ["navigation", "permissions", "breadcrumbs"],
                     surface: "LiveView",
                     host_os: "Linux",
                     theme: "light",
                     source_file: __ENV__.file
                   }
    setup_all do
      AtddEvidence.reset!("OUTREACH-NAV-01 · Compact menus and actual origins", @scenarios, %{
        browser: "Chromium",
        viewport: "390 / 768 / 1280",
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
        |> Ecto.Changeset.change(superadmin: true, name: "Synthetic Navigation Admin")
        |> Repo.update!()

      ordinary = user_fixture()
      manager = user_fixture()
      scope = Accounts.Scope.for_user(admin)
      {:ok, group} = Volunteers.create_group(scope, %{"name" => "Navigation reviewers"})
      {:ok, role} = Volunteers.assign_manager(scope, group.id, manager.email)
      old = Application.get_env(:pauseai_ca, :outreach_mailboxes)

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
        if old,
          do: Application.put_env(:pauseai_ca, :outreach_mailboxes, old),
          else: Application.delete_env(:pauseai_ca, :outreach_mailboxes)
      end)

      %{admin: admin, ordinary: ordinary, manager: manager, scope: scope, role: role}
    end

    for {locale, width, height} <- @flows do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "OUTREACH-NAV-01 permissions and two origins #{locale}", c do
        locale = unquote(locale)
        id = "OUTREACH-NAV-01-#{locale}-#{unquote(width)}"

        b =
          c.conn
          |> login(c.ordinary)
          |> visit("/#{locale}")
          |> assert_has("#section-navigation")
          |> absent("#manage-menu, #admin-menu, [data-navigation-item='pauseai.mail']")
          |> geometry()
          |> capture(
            id,
            "Ordinary account signs in → public home",
            "Only public and My Account sections; no Emails or management grants"
          )

        b =
          switch_browser_identity(b, &login(&1, c.manager))
          |> visit("/manage/mail?locale=#{locale}")
          |> assert_has("#manage-menu")
          |> absent("#admin-menu, [data-navigation-item='mail.conversations']")
          |> click("#manage-menu > summary")
          |> assert_has("#manage-menu [data-navigation-item='pauseai.mail']")
          |> capture(
            id,
            "Existing group manager opens Manage",
            "Legitimate scoped account-email tools remain; no ungranted Inbox"
          )

        {:ok, _} = Outreach.grant_mailbox(c.scope, "outreach_#{locale}", c.manager.id, 0)

        b =
          b
          |> click_link(
            "#manage-menu [data-navigation-item='pauseai.mail']",
            tr(locale, "Emails")
          )
          |> click_link("[data-navigation-item='mail.conversations']", tr(locale, "Inbox"))
          |> assert_has("#outreach-compose")
          |> absent("#admin-menu")
          |> capture(
            id,
            "Manage → Emails → Inbox after a mailbox grant",
            "Delegated Inbox is available without making the manager an administrator"
          )

        Repo.delete!(Repo.get!(PauseAiCa.Volunteers.Manager, c.role.id))

        b =
          b
          |> click_button(tr(locale, "Search"))
          |> assert_has("#outreach-no-access")
          |> absent("#manage-menu, #admin-menu, [data-navigation-item='pauseai.mail']")
          |> capture(
            id,
            "Current manager role removed → Search",
            "Fresh permissions remove management/email menus and clear mailbox content"
          )

        {:ok, record} =
          CRM.create(c.scope, %{
            "name" => "Synthetic navigation contact",
            "email" => "navigation-contact@example.org"
          })

        conv_id =
          if locale == "en",
            do: "c1000000-0000-4000-8000-000000000001",
            else: "c1000000-0000-4000-8000-000000000002"

        conv =
          Repo.insert!(%PhoenixCRM.Conversation{
            id: conv_id,
            mailbox_ref: "outreach_#{locale}",
            subject: "Synthetic navigation conversation",
            participants: ["navigation-partner@example.org"],
            actor_id: c.admin.id
          })

        Repo.insert!(%PhoenixCRM.Message{
          conversation_id: conv.id,
          mailbox_ref: conv.mailbox_ref,
          direction: :inbound,
          idempotency_key: conv.id,
          rfc_message_id: "<#{conv.id}@example.org>",
          actor_id: c.admin.id,
          outcome: :received,
          envelope: %{"from" => "navigation-partner@example.org", "subject" => conv.subject},
          body_text: "Synthetic navigation proof; no provider request."
        })

        b =
          switch_browser_identity(b, &login(&1, c.admin))
          |> visit("/#{locale}")
          |> click("#admin-menu > summary")
          |> click_link(
            "#admin-menu [data-navigation-item='pauseai.contacts']",
            tr(locale, "Contacts")
          )
          |> assert_has("#crm-contact-#{record.person.id}")
          |> click_button(
            "#crm-contact-#{record.person.id} button",
            tr(locale, "Invite to create an account")
          )
          |> assert_has("#crm-invitation-form")
          |> capture(
            id,
            "Admin → Contacts → Invite to create an account",
            "Contact invitation is the actual entry branch, without a fixed My Account/Admin prefix"
          )

        b =
          b
          |> fill_in(tr(locale, "Invitation from"), with: "Synthetic Navigation Admin")
          |> fill_in(tr(locale, "Why you are inviting them · English"),
            with: "Synthetic local invitation proof."
          )
          |> fill_in(tr(locale, "Why you are inviting them · French"),
            with: "Preuve locale fictive de navigation."
          )
          |> check(
            tr(locale, "I reviewed these contacts’ eligibility for this invitation or message.")
          )
          |> click_button(tr(locale, "Review invitation"))
          |> assert_has("#newsletter-draft")
          |> origin(tr(locale, "Contacts"), nil)
          |> capture(
            id,
            "Contacts invitation → Review invitation → shared editor",
            "The editor retains the actual Contacts origin"
          )

        b =
          b
          |> click("#manage-menu > summary")
          |> click_link(
            "#manage-menu [data-navigation-item='pauseai.mail']",
            tr(locale, "Emails")
          )
          |> assert_has("#mail-batches")
          |> click_link("[data-navigation-item='mail.conversations']", tr(locale, "Inbox"))
          |> assert_has("#outreach-conversations")
          |> click_link(nil, conv.subject)
          |> assert_path("/manage/mail/conversations/#{conv.id}")
          |> capture(
            id,
            "Manage → Emails → Inbox → conversation",
            "A new chosen top-level entry starts a different actual journey"
          )

        b =
          b
          |> click_button(tr(locale, "Reply"))
          |> assert_has("#newsletter-draft-form")
          |> origin(tr(locale, "Drafts"), tr(locale, "Contacts"))
          |> capture(
            id,
            "Inbox conversation → Reply → shared editor",
            "The same editor screen retains Inbox's origin, not the earlier Contacts branch"
          )

        evaluate(
          b,
          "[...document.querySelectorAll('#journey-breadcrumbs li')].map(x=>x.textContent)",
          &Process.put(:nav_expected_trail, &1)
        )

        evaluate(b, "location.pathname", &Process.put(:nav_editor_path, &1))
        b = b |> keyboard() |> geometry()

        b =
          evaluate(b, "history.back()")
          |> assert_path("/manage/mail/conversations/#{conv.id}")
          |> assert_has("#outreach-messages")

        b =
          evaluate(b, "history.forward()")
          |> assert_path(Process.get(:nav_editor_path))
          |> assert_has("#newsletter-draft-form")

        b = evaluate(b, "location.reload()") |> assert_has("#newsletter-draft-form")

        evaluate(
          b,
          "[...document.querySelectorAll('#journey-breadcrumbs li')].map(x=>x.textContent)",
          &assert(&1 == Process.get(:nav_expected_trail))
        )

        b =
          capture(
            b,
            id,
            "Browser Back → Forward → Reload",
            "Actual reply origin survives history restoration and reload"
          )

        assert Repo.aggregate(Accounts.User, :count) == 3
        assert Enum.all?(Repo.all(PauseAiCa.Newsletters.Delivery), &is_nil(&1.attempted_at))
        _ = b
        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      end
    end

    for {locale, width, height} <- @responsive do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "OUTREACH-NAV-01 responsive #{locale} #{width}", c do
        locale = unquote(locale)
        id = "OUTREACH-NAV-01-#{locale}-#{unquote(width)}"

        c.conn
        |> login(c.admin)
        |> visit("/manage/mail/access?locale=#{locale}")
        |> assert_has("#mailbox-access")
        |> keyboard()
        |> geometry()
        |> capture(
          id,
          "Superadmin opens mailbox access at #{unquote(width)}px",
          "Compact section menus, keyboard focus and page width fit this viewport"
        )

        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      end
    end

    defp login(b, user) do
      {token, _} = generate_user_magic_link_token(user)

      b
      |> visit("/users/log-in/#{token}?locale=en")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp absent(b, selector) do
      evaluate(
        b,
        "document.querySelectorAll(" <> Jason.encode!(selector) <> ").length",
        &assert(&1 == 0)
      )

      b
    end

    defp geometry(b) do
      evaluate(
        b,
        "({width:innerWidth,scroll:document.documentElement.scrollWidth,header:document.querySelector('header').getBoundingClientRect().height,bars:document.querySelectorAll('.management-chrome').length})",
        fn x ->
          assert x["scroll"] <= x["width"]
          assert x["header"] < 150
          assert x["bars"] == 0
        end
      )

      b
    end

    defp origin(b, expected, excluded) do
      b = assert_has(b, "#journey-breadcrumbs li", text: expected)

      evaluate(
        b,
        "[...document.querySelectorAll('#journey-breadcrumbs li')].map(x=>x.textContent)",
        fn labels ->
          assert hd(labels) == expected
          if excluded, do: refute(excluded in labels)
          refute "My account" in labels
          refute "Mon compte" in labels
        end
      )

      b
    end

    defp keyboard(b) do
      b =
        b
        |> press("#manage-menu > summary", "Enter")
        |> assert_has("#manage-menu[open]")
        |> press("#manage-menu > summary", "Tab")

      evaluate(b, "document.activeElement?.matches('#manage-menu a')", &assert(&1))

      b =
        b
        |> press("#manage-menu [data-navigation-item='pauseai.accounts']", "Escape")
        |> refute_has("#manage-menu[open]")

      evaluate(
        b,
        "document.activeElement === document.querySelector('#manage-menu > summary')",
        &assert(&1)
      )

      b
      |> click("#admin-menu > summary")
      |> assert_has("#admin-menu[open]")
      |> click("main h1")
      |> refute_has("#admin-menu[open]")
    end

    defp capture(b, id, control, outcome) do
      evaluate(b, "location.href", &Process.put(:nav_capture_url, AtddEvidence.safe_url(&1)))
      url = Process.get(:nav_capture_url)
      IO.puts("Capture URL: [#{url}](#{url}); preceding/control: #{control}")
      if String.contains?(url, "/manage/mail/drafts/"), do: announcement_gate(url, control)
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
          "Actual isolated local application; synthetic SQL sandbox users and data; no provider or real mail"
      })

      b
    end

    defp announcement_gate(url, control) do
      if root = System.get_env("NAV_CAPTURE_GATE_DIR") do
        File.mkdir_p!(root)
        sha = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)

        File.write!(
          Path.join(root, "pending.json"),
          Jason.encode!(%{url: url, control: control, sha: sha})
        )

        wait_announcement(Path.join(root, sha), System.monotonic_time(:millisecond) + 90_000)
      end
    end

    defp wait_announcement(file, until) do
      cond do
        File.exists?(file) ->
          :ok

        System.monotonic_time(:millisecond) >= until ->
          flunk("Local capture announcement pending; no screenshot taken")

        true ->
          Process.sleep(200)
          wait_announcement(file, until)
      end
    end

    defp tr(locale, key),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, key)
        end)
  end
end
