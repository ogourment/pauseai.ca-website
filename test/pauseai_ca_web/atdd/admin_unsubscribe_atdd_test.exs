if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.AdminUnsubscribeTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Newsletters, Repo}
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

        label = tr(locale, "Record unsubscribe request")

        browser =
          browser
          |> visit("/manage/mail/newsletters?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")

        for email <- ["first-#{locale}@example.org", "second-#{locale}@example.org"],
            reduce: browser do
          browser ->
            browser =
              browser
              |> click("details > summary", label)
              |> fill_in("#withdrawal_email", tr(locale, "Email"), with: email)
              |> fill_in("#withdrawal_reason", tr(locale, "Request details"),
                with: "Synthetic recipient request received today"
              )
              |> click_button("#newsletter-withdrawal button", label)
              |> assert_has("#flash-info",
                text:
                  tr(
                    locale,
                    "Unsubscribe request recorded. This address is excluded from newsletter and manual outreach sends."
                  )
              )

            refute Newsletters.outreach_eligible?(email)
            subscription = Repo.get_by!(Newsletters.Subscription, email: email)
            assert subscription.state == "withdrawn"

            browser
            |> visit("/manage/mail/newsletters?locale=#{locale}&q=#{URI.encode_www_form(email)}")
            |> assert_has("#newsletter-#{subscription.id}", text: email)
        end
      end
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)
  end
end
