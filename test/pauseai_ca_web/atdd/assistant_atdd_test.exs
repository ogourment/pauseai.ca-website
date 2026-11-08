if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.AssistantTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Assistant, AssistantFixtures, Repo}
    alias PauseAiCaWeb.AtddEvidence
    alias PhoenixAgentAssistant.Store
    @moduletag :atdd
    @scenarios [
      %{
        id: "CRM-ASSIST-01",
        title: "Enable assistant, preserve draft and account history",
        roles: ["Superadmin"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "CRM-ASSIST-TOKENS-01",
        title: "Per-admin quotas and fresh authorization",
        roles: ["Superadmin", "Revoked administrator"],
        language: "French",
        device: "Phone",
        source_file: __ENV__.file
      },
      %{
        id: "CRM-ASSIST-UX-01",
        title: "Safe Markdown navigation and retained draft during transient readiness",
        roles: ["Superadmin"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      }
    ]

    setup_all do
      AtddEvidence.reset!(
        "Application assistant · activation, conversation and token limits",
        @scenarios,
        %{
          browser: "Chromium",
          viewport: "1280×900 English desktop / 390×844 French phone",
          fixture: "Synthetic AssistantFixtures only; no provider network"
        }
      )

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      previous = Application.fetch_env(:pauseai_ca, :agent_assistant)
      previous_build = System.get_env("PAUSEAI_CA_RELEASE_ID")
      System.put_env("PAUSEAI_CA_RELEASE_ID", "assistant-synthetic-fixture")
      Application.put_env(:pauseai_ca, :agent_assistant, AssistantFixtures.configuration(self()))

      on_exit(fn ->
        case previous do
          {:ok, config} -> Application.put_env(:pauseai_ca, :agent_assistant, config)
          :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
        end

        if previous_build,
          do: System.put_env("PAUSEAI_CA_RELEASE_ID", previous_build),
          else: System.delete_env("PAUSEAI_CA_RELEASE_ID")
      end)

      admin =
        user_fixture(%{email: "assistant-browser-admin@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      other =
        user_fixture(%{email: "assistant-browser-other@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      flush_mail()

      %{
        admin: admin,
        other: other,
        scope: Accounts.Scope.for_user(admin),
        other_scope: Accounts.Scope.for_user(other)
      }
    end

    @tag screenshot: true
    @tag browser_context_opts: [viewport: %{width: 1280, height: 900}]
    test "CRM-ASSIST-01 OFF to real floating conversation and persistent account preference", c do
      id = "CRM-ASSIST-01"
      refute Store.enabled?(Assistant.store())

      browser =
        c.conn
        |> login(c.admin)
        |> visit("/admin/contacts?locale=en")
        |> connected()
        |> refute_has("#site-assistant-launcher")
        |> capture(
          id,
          "Assistant initially off",
          "Signed-in Contacts",
          "Open Contacts",
          "No launcher is present while the administrator-controlled assistant is off."
        )
        |> visit("/admin/assistant?locale=en")
        |> connected()
        |> assert_has("#assistant-status", text: "Off", exact: true)
        |> click_button("#assistant-enable", "Enable assistant")
        |> assert_has("#assistant-status", text: "On", exact: true)
        |> capture(
          id,
          "Administrator enables assistant",
          "Assistant settings with Off status",
          "Enable assistant",
          "The real settings form enables only the synthetic configured assistant. All model and safety adapters are local fixtures."
        )
        |> visit("/admin/contacts?locale=en")
        |> connected()
        |> assert_has(".phx-connected #site-assistant-launcher")
        |> click_button("#site-assistant-launcher", "Assistant")
        |> assert_has("#site-assistant-dialog[open]")
        |> assert_has("#site-assistant-mode", value: "fast")
        |> fill_in("#site-assistant-text", "Message", with: "Find contacts by recorded city")
        # Intentionally do not wait for the textarea debounce before changing mode.
        |> select("#site-assistant-mode", "Mode", option: "High")
        |> assert_has("#site-assistant-mode", value: "high")
        |> assert_has("#site-assistant-text", value: "Find contacts by recorded city")
        |> capture(
          id,
          "Immediate mode change preserves text",
          "Open floating assistant on Contacts",
          "Type Message; immediately choose High",
          "The unfinished text is retained while the account's chosen mode changes from Fast to High."
        )
        |> click_button("#site-assistant-form button[type=submit]", "Send")
        |> assert_has("#site-assistant-messages",
          text: "Use the contact filters to choose a city."
        )

      assert_receive {:assistant_generated, %{"text" => "Find contacts by recorded city"},
                      %{model: "opus-fixture", mode: "high"}},
                     5_000

      assert {:ok, %{reported_input: 70, reported_output: 10}} = Assistant.token_usage(c.scope)
      assert {:ok, reference} = Assistant.conversation(c.scope)
      assert {:ok, history} = Assistant.history(c.scope, reference)
      assert Enum.any?(history, &(&1.text == "Find contacts by recorded city"))
      assert Enum.any?(history, &(&1.text == "Use the contact filters to choose a city."))

      browser =
        browser
        |> capture(
          id,
          "Fixture reply and accounted tokens",
          "Retained draft in High mode",
          "Send",
          "Exactly one fixture provider call creates the user/reply history and records 70 input plus 10 output tokens; no external API is contacted."
        )
        |> visit("/admin/contacts?locale=en")
        |> connected()
        |> assert_has(".phx-connected #site-assistant-launcher")
        |> click_button("#site-assistant-launcher", "Assistant")
        |> assert_has("#site-assistant-mode", value: "high")
        |> assert_has("#site-assistant-messages", text: "Find contacts by recorded city")
        |> assert_has("#site-assistant-messages",
          text: "Use the contact filters to choose a city."
        )
        |> capture(
          id,
          "Account history and mode survive reload",
          "Completed fixture conversation",
          "Reload Contacts; reopen Assistant",
          "The persisted account mode and both conversation messages are restored from the consumer store."
        )
        |> click_button(nil, "New conversation", exact: true)
        |> refute_has("#site-assistant-messages",
          text: "Use the contact filters to choose a city."
        )
        |> assert_has("#site-assistant-mode", value: "high")
        |> capture(
          id,
          "New conversation retains account mode",
          "Reloaded prior conversation",
          "New conversation",
          "A new empty conversation keeps High mode. Prior history remains readable through the original stored conversation reference."
        )

      assert {:ok, retained} = Assistant.history(c.scope, reference)
      assert length(retained) == length(history)
      refute_receive {:assistant_generated, _, _}
      refute_received {:email, _}
      success(id)
      browser
    end

    @tag screenshot: true
    @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
    test "CRM-ASSIST-TOKENS-01 quota zero blocks provider and revoked admin cannot change another quota",
         c do
      id = "CRM-ASSIST-TOKENS-01"
      locale = "fr"

      browser =
        c.conn
        |> login(c.admin)
        |> visit("/admin/assistant?locale=fr")
        |> connected()
        |> click_button("#assistant-enable", tr(locale, "Enable assistant"))
        |> assert_has("#assistant-status", text: tr(locale, "On"), exact: true)
        |> capture(
          id,
          "Quota settings before editing",
          "French Assistant settings",
          "Enable assistant",
          "The controls retain their French accessible labels before the quota is changed."
        )
        |> set_limit(c.other.email, "25000", locale)

      assert {:ok, %{limit: 25_000}} = Assistant.token_usage(c.other_scope)
      assert {:ok, %{limit: 100_000}} = Assistant.token_usage(c.scope)

      browser =
        browser
        |> capture(
          id,
          "Separate administrator quota",
          "Enabled assistant settings",
          "Admin → synthetic other admin; Daily token limit → 25000; Save limit",
          "Only the selected administrator's quota changes; the acting administrator retains its default allowance."
        )
        |> set_limit(c.other.email, "0", locale)

      assert {:ok, %{limit: 0}} = Assistant.token_usage(c.other_scope)

      browser =
        browser
        |> capture(
          id,
          "Zero quota saved",
          "Other administrator quota 25000",
          "Daily token limit → 0; Save limit",
          "Zero disables new requests for the selected account without deleting its conversations or granting privileges."
        )
        |> switch_browser_identity(&login(&1, c.other))
        |> visit("/admin/contacts?locale=fr")
        |> connected()
        |> assert_has(".phx-connected #site-assistant-launcher")
        |> click_button("#site-assistant-launcher", tr(locale, "Assistant"))
        |> assert_has("#site-assistant-dialog[open]")
        |> assert_has("#site-assistant-usage",
          text:
            tr(locale, "%{remaining} / %{limit} tokens remaining today", remaining: 0, limit: 0)
        )
        |> assert_has("#site-assistant-form button[type=submit][disabled]")
        |> fill_in("#site-assistant-text", tr(locale, "Message"),
          with: "Synthetic quota-denied request"
        )
        |> capture(
          id,
          "No allowance prevents normal submission",
          "Other administrator signs in",
          "Open Assistant; type a request",
          "The real quota summary shows zero and Send is disabled. The unfinished request remains editable."
        )
        # Exercise the authenticated form's server boundary even if a client removes UI protection.
        |> evaluate("document.querySelector('#site-assistant-form').requestSubmit()")
        |> assert_has("#site-assistant .paa-error",
          text: tr(locale, "Your daily token allowance is exhausted. Your draft is retained.")
        )
        |> assert_has("#site-assistant-text", value: "Synthetic quota-denied request")
        |> capture(
          id,
          "Forged UI submission still fails closed",
          "Zero-allowance floating assistant",
          "Submit the native form despite disabled Send",
          "Server quota enforcement rejects the request before fixture generation; the draft is retained."
        )

      refute_receive {:assistant_generated, _, _}

      assert {:ok, %{limit: 0, reported_input: 0, reported_output: 0}} =
               Assistant.token_usage(c.other_scope)

      browser =
        browser
        |> switch_browser_identity(&login(&1, c.admin))
        |> visit("/admin/assistant?locale=fr")
        |> connected()
        |> select("#assistant-token-limit-form select", tr(locale, "Admin"),
          option: c.other.email,
          exact: false
        )
        |> fill_in(
          "#assistant-token-limit-form input[type=number]",
          tr(locale, "Daily token limit"),
          with: "50000"
        )

      c.admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

      browser =
        browser
        |> click_button("#assistant-token-limit-form button", tr(locale, "Save limit"))
        |> assert_has("#assistant-settings [role=alert]",
          text: tr(locale, "The token limit could not be changed.")
        )
        |> capture(
          id,
          "Fresh revocation denies quota changes",
          "An administrator's already-open settings form",
          "Revoke the synthetic actor's admin role; submit the previously opened quota form",
          "Fresh server authorization refuses the mutation. The target quota stays zero and no provider is called."
        )

      assert {:ok, %{limit: 0}} = Assistant.token_usage(c.other_scope)
      refute_receive {:assistant_generated, _, _}
      refute_received {:email, _}
      success(id)
      browser
    end

    @tag screenshot: true
    @tag browser_context_opts: [viewport: %{width: 1280, height: 900}]
    test "CRM-ASSIST-UX-01 rendered response navigates safely and unavailable readiness retains the draft",
         c do
      id = "CRM-ASSIST-UX-01"

      response =
        "## Recorded geography\n\n[Open Contacts](/admin/contacts?locale=en)\n\n<img src=\"https://images.example.invalid/private.png\" onerror=\"alert(1)\">"

      config = AssistantFixtures.configuration(self(), response_text: response)
      Application.put_env(:pauseai_ca, :agent_assistant, config)

      browser =
        c.conn
        |> login(c.admin)
        |> visit("/admin/assistant?locale=en")
        |> connected()
        |> click_button("#assistant-enable", "Enable assistant")
        |> assert_has("#assistant-status", text: "On", exact: true)
        |> visit("/admin/contacts?locale=en")
        |> connected()
        |> assert_has(".phx-connected #site-assistant-launcher")
        |> click_button("#site-assistant-launcher", "Assistant")
        |> assert_has("#site-assistant-dialog[open]")
        |> fill_in("#site-assistant-text", "Message", with: "Show the recorded contact filters")
        |> click_button("#site-assistant-form button[type=submit]", "Send")
        |> assert_has("#site-assistant-messages h2", text: "Recorded geography", exact: true)
        |> assert_has("#site-assistant-messages a[href='/admin/contacts?locale=en']",
          text: "Open Contacts"
        )
        |> assert_has("#site-assistant-messages", text: "<img src=")
        |> refute_has("#site-assistant-messages img")
        |> capture(
          id,
          "Rendered safe Markdown response",
          "Floating assistant on Contacts",
          "Type the synthetic question; Send",
          "The fixture response renders its heading and native Contacts link; raw image HTML remains literal text and creates no image element."
        )

      assert_receive {:assistant_generated, %{"text" => "Show the recorded contact filters"}, _},
                     5_000

      assert {:ok, reference} = Assistant.conversation(c.scope)
      assert {:ok, history} = Assistant.history(c.scope, reference)
      assert Enum.any?(history, &(&1.text == response))

      browser =
        browser
        |> click_link(
          "#site-assistant-messages a[href='/admin/contacts?locale=en']",
          "Open Contacts"
        )
        |> assert_path("/admin/contacts")
        |> connected()
        |> assert_has(".phx-connected #site-assistant-launcher")
        |> capture(
          id,
          "Native Contacts destination",
          "Rendered assistant response",
          "Open Contacts",
          "The response link performs real authorized navigation to Contacts, without asking a model to execute a tool."
        )
        |> click_button("#site-assistant-launcher", "Assistant")
        |> assert_has("#site-assistant-dialog[open]")
        |> assert_has("#site-assistant-messages h2", text: "Recorded geography", exact: true)
        |> fill_in("#site-assistant-text", "Message", with: "Retain this unfinished question")
        |> assert_has("#site-assistant-text", value: "Retain this unfinished question")
        |> capture(
          id,
          "Reopened history with unfinished draft",
          "Contacts reached through the assistant response",
          "Reopen Assistant; type a new question",
          "The stored Markdown response is restored after navigation, and the new unsent question remains editable."
        )

      Application.put_env(
        :pauseai_ca,
        :agent_assistant,
        Keyword.put(config, :operations_adapter, {AssistantFixtures.Operations, [ready: false]})
      )

      Phoenix.PubSub.broadcast(
        PauseAiCa.PubSub,
        "agent_assistant:settings",
        :assistant_settings_changed
      )

      browser =
        browser
        |> assert_has("#site-assistant .paa-error",
          text: "The assistant is temporarily unavailable. Your draft is retained."
        )
        |> assert_has("#site-assistant-launcher")
        |> assert_has("#site-assistant-dialog[open]")
        |> assert_has("#site-assistant-text", value: "Retain this unfinished question")
        |> assert_has("#site-assistant-form button[type=submit][disabled]")
        |> capture(
          id,
          "Readiness interruption preserves history and draft",
          "Reopened persisted response on Contacts",
          "Type an unfinished question; synthetic operations readiness becomes unavailable",
          "The enabled launcher, dialog, prior response and draft remain present. Send is disabled, and no further provider call occurs."
        )

      assert {:ok, retained} = Assistant.history(c.scope, reference)
      assert retained == history
      refute_receive {:assistant_generated, _, _}
      refute_received {:email, _}
      success(id)
      browser
    end

    defp set_limit(browser, email, limit, locale) do
      browser
      |> select("#assistant-token-limit-form select", tr(locale, "Admin"),
        option: email,
        exact: false
      )
      |> fill_in(
        "#assistant-token-limit-form input[type=number]",
        tr(locale, "Daily token limit"),
        with: limit
      )
      |> click_button("#assistant-token-limit-form button", tr(locale, "Save limit"))
      |> assert_has(
        "#assistant-token-limits tbody tr td[data-label='#{tr(locale, "Daily limit")}']",
        text: limit,
        exact: true
      )
    end

    defp login(browser, actor) do
      {token, _} = generate_user_magic_link_token(actor)

      browser
      |> visit("/users/log-in/#{token}?locale=en")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp connected(browser), do: assert_has(browser, "[data-phx-main].phx-connected")

    defp tr(locale, text, bindings \\ []),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text, bindings)
        end)

    defp flush_mail do
      receive do
        {:email, _} -> flush_mail()
      after
        0 -> :ok
      end
    end

    defp success(id),
      do: AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))

    defp capture(browser, id, title, preceding, control, outcome) do
      evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      step = Process.get({:assistant_step, id}, 0) + 1
      Process.put({:assistant_step, id}, step)
      filename = "#{id}-#{step}.png"
      evaluate(browser, "location.href", &Process.put(:assistant_capture_url, &1))
      url = AtddEvidence.safe_url(Process.get(:assistant_capture_url))
      IO.puts("Capture URL: #{url}")

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "fixture" => "AssistantFixtures; no external provider HTTP",
        "external_systems" =>
          "Isolated synthetic accounts and local database only; no external sends or paid API calls"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, title, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        title,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
