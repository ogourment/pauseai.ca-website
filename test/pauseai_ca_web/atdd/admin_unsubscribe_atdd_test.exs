if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.AdminUnsubscribeTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, CRM, Newsletters, Repo}
    @moduletag :atdd

    for {locale, width} <- [{"en", 1280}, {"fr", 390}] do
      @tag browser_context_opts: [viewport: %{width: width, height: 900}]
      test "administrator records two requested addresses and verifies withdrawal after reload #{locale}",
           c do
        locale = unquote(locale)
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        {token, _} = generate_user_magic_link_token(admin)

        browser =
          c.conn
          |> visit("/users/log-in/#{token}?locale=en")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")

        label = tr(locale, "Unsubscribe")

        browser =
          browser
          |> visit("/manage/mail/newsletters?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")

        capture(browser, locale, "lists")

        for email <- ["first-#{locale}@example.org", "second-#{locale}@example.org"],
            reduce: browser do
          browser ->
            browser =
              browser
              |> click("#mail-more > summary", tr(locale, "More"))
              |> click_link("#mail-more a", tr(locale, "Email preferences"))
              |> assert_has("[data-phx-main].phx-connected #email-preferences")
              |> capture(locale, "manual-form")
              |> fill_in("#withdrawal_email", tr(locale, "Email"), with: email)
              |> fill_in("#withdrawal_reason", tr(locale, "Request details"),
                with: "Synthetic recipient request received today"
              )
              |> click_button("#newsletter-withdrawal button", label)
              |> assert_has("#withdrawal-result",
                text:
                  tr(
                    locale,
                    "Unsubscribe request recorded."
                  )
              )

            capture(browser, locale, "manual-result")
            refute Newsletters.outreach_eligible?(email)
            subscription = Repo.get_by!(Newsletters.Subscription, email: email)
            assert subscription.state == "withdrawn"

            browser
            |> visit("/manage/mail/newsletters?locale=#{locale}&q=#{URI.encode_www_form(email)}")
            |> assert_has("#newsletter-#{subscription.id}", text: email)
        end
      end
    end

    for {locale, width} <- [{"en", 1280}, {"fr", 390}] do
      @tag browser_context_opts: [viewport: %{width: width, height: 900}]
      test "contact selects both addresses and reloads their withdrawal #{locale}", c do
        locale = unquote(locale)
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

        {:ok, record} =
          CRM.create(Accounts.Scope.for_user(admin), %{
            "name" => "Synthetic contact",
            "email" => "contact-one-#{locale}@example.org"
          })

        Repo.insert!(%PhoenixCRM.Address{
          person_id: record.person.id,
          email: "contact-two-#{locale}@example.org"
        })

        {token, _} = generate_user_magic_link_token(admin)

        browser =
          c.conn
          |> visit("/users/log-in/#{token}?locale=en")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/admin/contacts/#{record.person.id}?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected #crm-email-preferences")
          |> capture(locale, "contact")
          |> click_link("#crm-email-preferences", tr(locale, "Email preferences"))
          |> assert_has("[data-phx-main].phx-connected #email-preferences")
          |> capture(locale, "contact-preferences")

        browser =
          Enum.reduce(
            ["contact-one-#{locale}@example.org", "contact-two-#{locale}@example.org"],
            browser,
            fn email, browser ->
              check(
                browser,
                "input[value='#{email}']",
                email <> " · " <> tr(locale, "No withdrawal recorded")
              )
            end
          )

        browser =
          browser
          |> fill_in(tr(locale, "Request details"),
            with: "Synthetic request covering both addresses"
          )
          |> click_button("#newsletter-withdrawal button", tr(locale, "Unsubscribe"))
          |> assert_has("#withdrawal-result", text: "contact-one-#{locale}@example.org")
          |> assert_has("#withdrawal-result", text: "contact-two-#{locale}@example.org")
          |> capture(locale, "contact-result")

        for email <- ["contact-one-#{locale}@example.org", "contact-two-#{locale}@example.org"],
            do: refute(Newsletters.outreach_eligible?(email))

        browser
        |> visit("/manage/mail/preferences?locale=#{locale}&contact_id=#{record.person.id}")
        |> assert_has("#newsletter-withdrawal", text: tr(locale, "Withdrawn"))
      end
    end

    for {locale, width} <- [{"en", 1280}, {"fr", 390}] do
      @tag accept_dialogs: false
      @tag browser_context_opts: [viewport: %{width: width, height: 900}]
      test "quiet bottom unsubscribe action requires confirmation #{locale}", c do
        locale = unquote(locale)
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        {token, _} = generate_user_magic_link_token(admin)

        browser =
          c.conn
          |> visit("/users/log-in/#{token}?locale=en")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/manage/mail/preferences?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected #email-preferences")
          |> fill_in(tr(locale, "Email"), with: "confirmation-#{locale}@example.org")
          |> fill_in(tr(locale, "Request details"), with: "Synthetic request")
          |> capture(locale, "quiet-link")

        {:ok, appearance} =
          PlaywrightEx.Frame.evaluate(browser.frame_id,
            expression:
              "(() => {const e=document.querySelector('#newsletter-withdrawal button'), s=getComputedStyle(e), r=e.getBoundingClientRect(), t=document.querySelector('#withdrawal_reason').getBoundingClientRect(); return {background:s.backgroundColor,underlined:s.textDecorationLine.includes('underline'),below:r.y>=t.bottom,font:parseFloat(s.fontSize),width:r.width}})()",
            timeout: 8_000
          )

        assert appearance["background"] == "rgba(0, 0, 0, 0)"
        assert appearance["underlined"] and appearance["below"]
        assert appearance["font"] <= 14 and appearance["width"] < 200

        message =
          tr(
            locale,
            "Unsubscribe the selected addresses? Pending sends will check withdrawal before dispatch."
          )

        owner = self()

        browser =
          with_dialog(
            browser,
            fn %{message: actual} ->
              send(owner, {:confirmation, actual})
              :dismiss
            end,
            fn b ->
              click_button(b, "#newsletter-withdrawal button", tr(locale, "Unsubscribe"))
            end
          )

        assert_receive {:confirmation, ^message}
        refute Repo.get_by(Newsletters.Subscription, email: "confirmation-#{locale}@example.org")

        browser =
          with_dialog(
            browser,
            fn %{message: actual} ->
              send(owner, {:confirmation, actual})
              :accept
            end,
            fn b ->
              b
              |> click_button("#newsletter-withdrawal button", tr(locale, "Unsubscribe"))
              |> assert_has("#withdrawal-result", text: "confirmation-#{locale}@example.org")
            end
          )

        assert_receive {:confirmation, ^message}
        refute Newsletters.outreach_eligible?("confirmation-#{locale}@example.org")
        capture(browser, locale, "quiet-link-result")
      end
    end

    defp capture(browser, locale, name) do
      if System.get_env("SLATE_CAPTURE") do
        {:ok, url} =
          PlaywrightEx.Frame.evaluate(browser.frame_id,
            expression: "location.href",
            timeout: 8_000
          )

        IO.puts("Before capture: #{url}")
        filename = "slate-v2-#{locale}-#{name}.png"
        browser = PauseAiCaWeb.AtddEvidence.capture_full_page(browser, filename)
        File.mkdir_p!("tmp/slate-captures")

        for suffix <- ["", ".html"],
            do:
              File.cp!(
                "tmp/atdd/screenshots/" <> filename <> suffix,
                "tmp/slate-captures/" <> filename <> suffix
              )

        File.write!("tmp/slate-captures/" <> filename <> ".url", url)
        browser
      else
        browser
      end
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)
  end
end
