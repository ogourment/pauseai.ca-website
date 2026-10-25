if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.SlackCommunityTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Repo, SlackFixtures}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @moduletag accept_dialogs: true
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "CHAT-PAI-01-#{locale}",
                    title: "Scoped Slack conversations · #{language}",
                    tags: ["community", "slack"],
                    roles: ["Explicitly linked member"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)
    setup_all do
      AtddEvidence.reset!("CHAT-PAI-01 · synthetic provider/local UI boundary", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CHAT-PAI-01 synthetic browse, thread, draft and uncertain post #{locale}", c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      previous = SlackFixtures.configure!()
      on_exit(fn -> SlackFixtures.restore!(previous) end)
      user = user_fixture()
      scope = Accounts.Scope.for_user(user)
      SlackFixtures.connect!(scope)
      {token, _} = generate_user_magic_link_token(user)

      b =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/#{locale}")
        |> PhoenixTest.Playwright.click("#account-menu summary")
        |> capture(
          locale,
          "Account menu before Conversations",
          "Click Conversations in My account"
        )
        |> click_link(
          "#account-navigation [data-navigation-item='pauseai.conversations']",
          tr(locale, "Conversations"),
          exact: true
        )
        |> connected()
        |> assert_has("#slack-community")
        |> assert_has("#slack-channel select", value: "C1")
        |> capture(
          locale,
          "Linked synthetic account opens Conversations",
          "Click Capture recent Slack history; provider responses are injected fixtures"
        )
        |> click_button(tr(locale, "Capture recent Slack history"))
        |> assert_has("#slack-messages", text: "Synthetic retained needle", exact: false)
        |> click_button(tr(locale, "Capture thread replies"))
        |> assert_has("#slack-messages", text: "Synthetic thread reply", exact: false)
        |> capture(
          locale,
          "Retained roots and threads",
          "Search for needle in retained conversations"
        )
        |> fill_in(tr(locale, "Search retained conversations"), with: "needle")
        |> click_button("#slack-search button[type=submit]", tr(locale, "Search"), exact: true)
        |> assert_has("#slack-messages", text: "Synthetic retained needle", exact: false)
        |> refute_has("#slack-messages", text: "Synthetic thread reply", exact: false)
        |> capture(locale, "Scoped retained search", "Click Reply on the selected root")
        |> click_button(
          "[phx-click=reply][phx-value-ts='1800000000.000001']",
          tr(locale, "Reply"),
          exact: true
        )
        |> fill_in(tr(locale, "Message"), with: "Synthetic reviewed reply")
        |> click_button(tr(locale, "Save draft"))
        |> assert_has("#slack-post-review", text: "Synthetic reviewed reply", exact: false)
        |> assert_has("#slack-post-review", text: "1800000000.000001", exact: false)
        |> capture(
          locale,
          "Saved exact channel/thread review",
          "Click Post to Slack and accept the exact-message confirmation; no real Slack request occurs"
        )
        |> click_button(tr(locale, "Post to Slack"))
        |> assert_has("#slack-post-status", text: tr(locale, "Posted to Slack"))
        |> capture(
          locale,
          "Synthetic provider accepts the reviewed reply",
          "Start a new channel message; the accepted timestamp is fixture data"
        )
        |> click_button(tr(locale, "Write a new channel message"))
        |> fill_in(tr(locale, "Message"), with: "Synthetic uncertain root")
        |> click_button(tr(locale, "Save draft"))
        |> assert_has("#slack-post-review", text: "Synthetic uncertain root", exact: false)

      PhoenixTest.Playwright.evaluate(
        b,
        "Array.from(document.querySelector('#slack-channel select').options).map(o=>({value:o.value,text:o.textContent}))",
        fn options -> assert options == [%{"value" => "C1", "text" => "general"}] end
      )

      Application.put_env(:pauseai_ca, :slack_test_post_mode, :uncertain)

      b =
        b
        |> click_button(tr(locale, "Post to Slack"))
        |> assert_has("#slack-post-status", text: tr(locale, "Delivery uncertain — do not retry"))
        |> refute_has("#slack-post-review button", text: tr(locale, "Post to Slack"))
        |> capture(
          locale,
          "Ambiguous transport outcome retains the draft",
          "No retry control is offered; fresh provider revocation is checked next"
        )

      assert Application.get_env(:pauseai_ca, :slack_test_post_count) == 2
      Application.put_env(:pauseai_ca, :slack_test_revoked, true)

      b =
        b
        |> visit("/community/slack?locale=#{locale}")
        |> connected()
        |> refute_has("#slack-messages")
        |> refute_has("#slack-channel")
        |> assert_has("#slack-saved-drafts", text: "Synthetic uncertain root", exact: false)
        |> capture(
          locale,
          "Fresh channel revocation clears retained conversation access",
          "Only the member's own saved drafts remain; provider fixtures made no external calls"
        )

      assert Application.get_env(:pauseai_ca, :slack_test_post_count) == 2

      AtddEvidence.mark_scenario_success!(
        Enum.find(@scenarios, &(&1.id == "CHAT-PAI-01-#{locale}"))
      )

      b
    end

    defp connected(browser), do: assert_has(browser, "[data-phx-main].phx-connected")

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, locale, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      id = "CHAT-PAI-01-#{locale}"
      step = Process.get({:slack_step, locale}, 0) + 1
      Process.put({:slack_step, locale}, step)
      file = "#{id}-#{step}.png"

      PhoenixTest.Playwright.evaluate(
        browser,
        "location.href",
        &Process.put(:slack_capture_url, &1)
      )

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "control" => control,
        "url" => AtddEvidence.safe_url(Process.get(:slack_capture_url)),
        "external_systems" =>
          "Synthetic OAuth/provider transports and local database only. No Slack installation, real account link or external message."
      }

      AcceptanceHarness.Evidence.record_pending_step(file, control, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, file)

      AtddEvidence.record_step(
        file,
        control,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
