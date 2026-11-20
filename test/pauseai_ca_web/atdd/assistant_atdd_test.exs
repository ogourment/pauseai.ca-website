if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.AssistantTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Assistant, AssistantFixtures, Repo}
    alias PauseAiCa.Assistant.Instructions
    alias PauseAiCaWeb.AtddEvidence
    alias PhoenixAgentAssistant.Store
    @moduletag :atdd
    @scenarios [
      %{
        id: "VOL-ASSIST-ACCESS-01",
        title: "Organizer reads a coaching response and loses access after revocation",
        roles: ["Group organizer"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "CRM-ASSIST-LAUNCHER-01-en",
        title: "Movable assistant leaves social links accessible",
        roles: ["Superadmin"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "CRM-ASSIST-LAUNCHER-01-fr",
        title: "Movable assistant leaves social links accessible",
        roles: ["Superadmin"],
        language: "French",
        device: "Phone",
        source_file: __ENV__.file
      },
      %{
        id: "CRM-ASSIST-CREDIT-01-en",
        title: "Credit warning and account availability beside the enable control",
        roles: ["Superadmin"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "CRM-ASSIST-CREDIT-01-fr",
        title: "Credit warning and account availability beside the enable control",
        roles: ["Superadmin"],
        language: "French",
        device: "Phone",
        source_file: __ENV__.file
      },
      %{
        id: "CRM-ASSIST-SOCIAL-01-en",
        title: "Official Canadian social links in the footer",
        roles: ["Public reader"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "CRM-ASSIST-SOCIAL-01-fr",
        title: "Official Canadian social links in the footer",
        roles: ["Public reader"],
        language: "French",
        device: "Phone",
        source_file: __ENV__.file
      },
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
      },
      %{
        id: "CRM-ASSIST-REVIEW-01-en",
        title: "Input review hold keeps the question and links protected details",
        roles: ["Superadmin"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "CRM-ASSIST-REVIEW-01-fr",
        title: "Input review hold keeps the question and links protected details",
        roles: ["Superadmin"],
        language: "French",
        device: "Phone",
        source_file: __ENV__.file
      },
      %{
        id: "AI-INSTR-01-en",
        title: "Restricted instructions, saved draft and explicit publication",
        roles: ["Allowlisted superadmin", "Other superadmin", "Group manager"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "AI-INSTR-01-fr",
        title: "Restricted instructions, saved draft and explicit publication",
        roles: ["Allowlisted superadmin", "Other superadmin", "Group manager"],
        language: "French",
        device: "Phone",
        source_file: __ENV__.file
      },
      %{
        id: "ASSIST-INPUT-01-en",
        title: "Approve a held input and generate its original contextual turn once",
        roles: ["Requester", "Superadmin reviewer", "Revoked reviewer"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "ASSIST-INPUT-01-fr",
        title: "Approve a held input and generate its original contextual turn once",
        roles: ["Requester", "Superadmin reviewer", "Revoked reviewer"],
        language: "French",
        device: "Phone",
        source_file: __ENV__.file
      },
      %{
        id: "ASSIST-EXCHANGE-01-en",
        title: "Inspect a held exchange, confirm its release and show local activity times",
        roles: ["Requester", "Superadmin reviewer", "Revoked reviewer"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "ASSIST-EXCHANGE-01-fr",
        title: "Inspect a held exchange, confirm its release and show local activity times",
        roles: ["Requester", "Superadmin reviewer", "Revoked reviewer"],
        language: "French",
        device: "Phone",
        source_file: __ENV__.file
      }
    ]

    defmodule UncertainInput do
      def review(_, _) do
        {:ok,
         %{
           risk: :review,
           probabilities: %{"low" => 0.75, "block" => 0.01},
           model: "synthetic-review"
         }}
      end
    end

    setup_all do
      AtddEvidence.reset!(
        "Application assistant · settings, private instructions and conversations",
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
      previous_editors = Application.fetch_env(:pauseai_ca, :assistant_instruction_editors)
      previous_build = System.get_env("PAUSEAI_CA_RELEASE_ID")
      System.put_env("PAUSEAI_CA_RELEASE_ID", "assistant-synthetic-fixture")
      Application.put_env(:pauseai_ca, :agent_assistant, AssistantFixtures.configuration(self()))
      Application.put_env(:pauseai_ca, :assistant_instruction_editors, [])

      on_exit(fn ->
        case previous do
          {:ok, config} -> Application.put_env(:pauseai_ca, :agent_assistant, config)
          :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
        end

        case previous_editors do
          {:ok, editors} ->
            Application.put_env(:pauseai_ca, :assistant_instruction_editors, editors)

          :error ->
            Application.delete_env(:pauseai_ca, :assistant_instruction_editors)
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
    test "VOL-ASSIST-ACCESS-01 organizer opens chat from My profile", c do
      organizer = user_fixture(%{email: "synthetic-ottawa-organizer@example.org"})
      {:ok, group} = PauseAiCa.Volunteers.create_group(c.scope, %{name: "Ottawa"})
      {:ok, grant} = PauseAiCa.Volunteers.assign_manager(c.scope, group.id, organizer.email)
      config = Application.fetch_env!(:pauseai_ca, :agent_assistant)
      {module, opts} = config[:provider]
      reply = "Open Manage → Tasks, choose Ottawa and select Add task."

      Application.put_env(
        :pauseai_ca,
        :agent_assistant,
        Keyword.put(config, :provider, {module, Keyword.put(opts, :response_text, reply)})
      )

      {:ok, _} = Assistant.set_enabled(c.scope, true)

      b =
        c.conn
        |> login(organizer)
        |> visit("/en/profile")
        |> connected()
        |> click_button("#site-assistant-launcher", "Assistant")
        |> fill_in("#site-assistant-text", "Message", with: "Where can I assign the march video?")
        |> click_button("#site-assistant-form button[type=submit]", "Send")
        |> assert_has("#site-assistant-messages", text: reply)
        |> capture(
          "VOL-ASSIST-ACCESS-01",
          "Organizer chat",
          "My profile",
          "Send",
          "Synthetic provider response in the organizer’s conversation"
        )

      assert_receive {:assistant_generated, _, _}
      :ok = PauseAiCa.Volunteers.revoke_manager(c.scope, grant.id)

      b
      |> fill_in("#site-assistant-text", "Message", with: "Continue")
      |> refute_has("#site-assistant-launcher")

      refute_receive {:assistant_generated, _, _}
      success("VOL-ASSIST-ACCESS-01")
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
      assert {:ok, retained_reference} = Assistant.conversation(c.other_scope)
      assert {:ok, retained_history} = Assistant.history(c.other_scope, retained_reference)

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
        |> refute_has("#site-assistant-launcher")
        |> refute_has("#site-assistant-dialog[open]")
        |> capture(
          id,
          "Zero allocation hides the assistant launcher",
          "Other administrator signs in with zero allocation",
          "Open the French Contacts page",
          "The zero-allocation account has no assistant popup. Existing conversations remain stored and no provider request is admitted."
        )

      requests_before = Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count)
      audit_before = Repo.aggregate(PhoenixAgentAssistant.Store.AuditEntry, :count)
      refute Assistant.launcher_visible?(c.other_scope)

      assert {:error, :unavailable} =
               Assistant.run(
                 c.other_scope,
                 Ecto.UUID.generate(),
                 "Synthetic quota-denied request",
                 retained_reference,
                 locale
               )

      assert Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count) == requests_before
      assert Repo.aggregate(PhoenixAgentAssistant.Store.AuditEntry, :count) == audit_before
      assert requests_before == 0

      assert {:ok, ^retained_history} =
               PhoenixAgentAssistant.History.read(
                 Assistant.store(),
                 c.other.id,
                 retained_reference,
                 Assistant.configuration()[:audit_keys]
               )

      refute_receive {:assistant_generated, _, _}

      assert {:ok, %{limit: 0, reported_input: 0, reported_output: 0}} =
               Assistant.token_usage(c.other_scope)

      browser =
        browser
        |> switch_browser_identity(&login(&1, c.admin))
        |> visit("/admin/assistant?locale=fr")
        |> connected()
        |> select("#assistant-token-limit-form select", tr(locale, "Account"),
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
        |> visit("/admin/contacts?locale=en")
        |> connected()
        |> click_button("#site-assistant-launcher", "Assistant")
        |> assert_has("#site-assistant-text", value: "Retain this unfinished question")
        |> capture(
          id,
          "Reload restores the unfinished draft",
          "Contacts reached through the assistant response",
          "Reopen Assistant; type a new question",
          "The stored Markdown response is restored after navigation, and the new unsent question remains editable."
        )

      browser =
        browser
        |> evaluate(
          "new Promise(resolve => window.liveSocket.disconnect(() => resolve(true)))",
          &assert(&1)
        )
        |> evaluate("window.liveSocket.isConnected()", &refute(&1))
        |> assert_has("#site-assistant-text", value: "Retain this unfinished question")
        |> reconnect_assistant()
        |> open_assistant_if_closed()
        |> assert_has(".phx-connected #site-assistant-text",
          value: "Retain this unfinished question"
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
          text: "Send is paused while the assistant’s monitoring connection recovers."
        )
        |> assert_has("#site-assistant-launcher")
        |> assert_has("#site-assistant-dialog[open]")
        |> assert_has("#site-assistant-text", value: "Retain this unfinished question")
        |> assert_has("#site-assistant-form button[type=submit][disabled]")
        |> visit("/admin/contacts?locale=en")
        |> connected()
        |> click_button("#site-assistant-launcher", "Assistant")
        |> assert_has("#site-assistant-text", value: "Retain this unfinished question")
        |> assert_has("#site-assistant-form button[type=submit][disabled]")
        |> capture(
          id,
          "Reload during a readiness interruption preserves the draft",
          "Reopened persisted response on Contacts",
          "Type an unfinished question; synthetic operations readiness becomes unavailable",
          "The enabled launcher, dialog, prior response and draft remain present. Send is disabled, and no further provider call occurs."
        )

      assert {:ok, retained} = Assistant.history(c.scope, reference)
      assert retained == history
      refute_receive {:assistant_generated, _, _}
      Application.put_env(:pauseai_ca, :agent_assistant, config)

      Phoenix.PubSub.broadcast(
        PauseAiCa.PubSub,
        "agent_assistant:settings",
        :assistant_settings_changed
      )

      browser =
        browser
        |> assert_has("#site-assistant-form button[type=submit]:not([disabled])")
        |> assert_has("#site-assistant-text", value: "Retain this unfinished question")
        |> click_button("#site-assistant-form button[type=submit]", "Send")
        |> assert_has("#site-assistant-text", value: "")
        |> visit("/admin/contacts?locale=en")
        |> connected()
        |> click_button("#site-assistant-launcher", "Assistant")
        |> assert_has("#site-assistant-text", value: "")
        |> fill_in("#site-assistant-text", "Message", with: "Discard through New conversation")
        |> click_button("#site-assistant-new", "+")
        |> assert_has("#site-assistant-text", value: "")
        |> visit("/admin/contacts?locale=en")
        |> connected()
        |> click_button("#site-assistant-launcher", "Assistant")
        |> assert_has("#site-assistant-text", value: "")
        |> capture(
          id,
          "Recovered Send and explicit draft clearing",
          "Retained question after readiness recovery",
          "Send; reload; type a draft; New conversation; reload",
          "Availability recovers automatically. A successful submission and an explicit New conversation clear their matching drafts."
        )

      refute_received {:email, _}
      success(id)
      browser
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-ASSIST-REVIEW-01-#{locale} input hold preserves the question and exposes protected review details",
           c do
        locale = unquote(locale)
        id = "CRM-ASSIST-REVIEW-01-#{locale}"
        config = AssistantFixtures.configuration(self())

        safety =
          Keyword.put(config[:safety], :jev, {UncertainInput, [api_key: "synthetic-review"]})

        Application.put_env(:pauseai_ca, :agent_assistant, Keyword.put(config, :safety, safety))
        assert {:ok, _} = Assistant.set_enabled(c.scope, true)
        question = "How can I find the most recent candidates for onboarding?"

        message =
          if locale == "fr",
            do:
              "Le contrôle automatique a retenu votre demande avant la génération d’une réponse.",
            else: "The automatic input review held your request before answer generation."

        send_label = if locale == "fr", do: "Envoyer", else: "Send"

        details_label =
          if locale == "fr", do: "Détails du contrôle", else: "Review details"

        browser =
          c.conn
          |> login(c.admin)
          |> visit("/admin/contacts?locale=#{locale}")
          |> connected()
          |> assert_has(".phx-connected #site-assistant-launcher")
          |> click_button("#site-assistant-launcher", "Assistant")
          |> fill_in("#site-assistant-text", "Message", with: question)
          |> click_button("#site-assistant-form button[type=submit]", send_label)
          |> assert_has("#site-assistant-error", text: message)
          |> assert_has("#site-assistant-text", value: question)
          |> assert_has("#site-assistant-form button[type=submit]:not([disabled])")
          |> assert_has("#site-assistant-error a[href*='/admin/assistant/activity/requests/']",
            text: details_label
          )
          |> capture(
            id,
            "Explicit input-review hold",
            "Assistant on Contacts",
            "Send the synthetic onboarding question with a75% fixture review",
            "The request is retained, the input phase is explained, and a protected review-details link is available. The fixture deliberately remains held; it does not claim a real classifier result."
          )

        refute_receive {:assistant_generated, _, _}
        success(id)
        browser
      end
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [
             viewport: %{width: width, height: height},
             timezoneId: "America/Toronto"
           ]
      test "ASSIST-EXCHANGE-01-#{locale} inspect and approve a held answer with local times", c do
        locale = unquote(locale)
        id = "ASSIST-EXCHANGE-01-#{locale}"
        config = Application.fetch_env!(:pauseai_ca, :agent_assistant)

        safety =
          Keyword.put(
            config[:safety],
            :jev,
            {AssistantFixtures.HeldOutput, [api_key: "synthetic-review"]}
          )

        Application.put_env(:pauseai_ca, :agent_assistant, Keyword.put(config, :safety, safety))
        assert {:ok, _} = Assistant.set_enabled(c.scope, true)
        assert {:ok, conversation} = Assistant.conversation(c.scope)
        reference = Ecto.UUID.generate()
        question = "How can I find Toronto contacts?"

        assert {:error, :output_safety_review_required} =
                 Assistant.run(c.scope, reference, question, conversation, locale)

        assert_receive {:assistant_generated, _, _}
        import Ecto.Query

        Repo.update_all(
          from(e in PhoenixAgentAssistant.Store.AuditEntry,
            join: stream in PhoenixAgentAssistant.Store.Stream,
            on: e.stream_id == stream.id,
            where: stream.namespace == ^Assistant.store().namespace
          ),
          set: [inserted_at: ~U[2026-11-16 02:02:48.000000Z]]
        )

        path = "/admin/assistant/activity/requests/#{reference}?locale=#{locale}"

        browser =
          c.conn
          |> login(c.other)
          |> visit("/admin/assistant/activity?locale=#{locale}")
          |> connected()
          |> capture(
            id,
            "Find a held request",
            "Admin → Assistant → Activity & security",
            "Open Activity & security",
            "The protected activity list links to its exact request."
          )
          |> click_link(
            "#assistant-audit-table a[href*='#{reference}']",
            tr(locale, "Request recorded")
          )
          |> assert_has("#assistant-review-question", text: question)
          |> assert_has("#assistant-review-answer",
            text: "Use the contact filters to choose a city."
          )
          |> assert_has("#assistant-review-approve", text: tr(locale, "Approve answer"))

        evaluate(
          browser,
          "Array.from(document.querySelectorAll('#assistant-audit-table time')).map(x => ({text:x.textContent,iso:x.dateTime,locale:x.dataset.locale}))",
          fn times ->
            assert times != []

            for time <- times do
              assert time["locale"] == locale
              assert time["iso"] =~ "2026-11-16T02:02:48"
              assert time["text"] =~ if(locale == "fr", do: "21:02:48", else: "9:02:48")
              assert time["text"] =~ if(locale == "fr", do: "15 nov.", else: "Nov 15")
            end
          end
        )

        browser =
          browser
          |> capture(
            id,
            "Read the retained question and held answer",
            "Protected activity list",
            "Request recorded; equivalent to the Telegram request link",
            "The exact retained exchange and clear Approve answer / Reject answer controls are visible. Times use the browser’s Toronto timezone."
          )
          |> click_button("#assistant-review-approve", tr(locale, "Approve answer"))
          |> fill_in("#assistant-review-reason", tr(locale, "Reason (optional)"),
            with: "Reviewed this synthetic answer"
          )
          |> click_button("#assistant-review-confirm", tr(locale, "Confirm approval"))
          |> assert_has("#assistant-review-decision-error",
            text: tr(locale, "Confirm that you reviewed the displayed answer.")
          )
          |> assert_has("#assistant-review-reason", value: "Reviewed this synthetic answer")
          |> capture(
            id,
            "Confirmation preserves the review reason",
            "Held answer → Approve answer",
            "Type an optional reason; Confirm approval without checking the acknowledgement",
            "The confirmation remains open, the reason is retained, and the acknowledgement is required."
          )
          |> check(
            "#assistant-review-confirmed",
            tr(locale, "I reviewed the displayed question, answer and review results.")
          )
          |> click_button("#assistant-review-confirm", tr(locale, "Confirm approval"))
          |> assert_has("#assistant-exchange-status",
            text: tr(locale, "Approved · The answer is available in its conversation history."),
            exact: true
          )
          |> refute_has("#assistant-review-approve")
          |> capture(
            id,
            "Approval recorded for the existing answer",
            "Completed confirmation",
            "Confirm approval",
            "The existing answer is released once; its decision and optional reason are durable."
          )
          |> visit(path)
          |> connected()
          |> assert_has("#assistant-human-review-receipt", text: "Reviewed this synthetic answer")
          |> refute_has("#assistant-review-approve")
          |> switch_browser_identity(&login(&1, c.admin))
          |> visit("/admin/contacts?locale=#{locale}")
          |> connected()
          |> click_button("#site-assistant-launcher", "Assistant")
          |> assert_has(".paa-message[data-role=assistant]",
            text: "Use the contact filters to choose a city."
          )
          |> capture(
            id,
            "Released answer in conversation history",
            "Approved request after reload",
            "Contacts → Assistant",
            "The original retained answer appears in its conversation history. Approval creates no new provider request."
          )

        refute_receive {:assistant_generated, _, _}
        assert {:ok, [_, _]} = Assistant.history(c.scope, conversation)

        browser =
          browser
          |> switch_browser_identity(&login(&1, c.other))
          |> visit(path)
          |> connected()
          |> assert_has("#assistant-review-answer",
            text: "Use the contact filters to choose a city."
          )
          |> assert_has("#assistant-human-review-receipt", text: "Reviewed this synthetic answer")
          |> refute_has("#assistant-review-approve")
          |> capture(
            id,
            "Superadmin review receipt survives identity changes",
            "Requester conversation history",
            "Sign in as the reviewing superadmin; open the protected request link",
            "The superadmin can review another requester's saved exchange and durable approval."
          )

        second_reference = Ecto.UUID.generate()

        assert {:error, :output_safety_review_required} =
                 Assistant.run(
                   c.scope,
                   second_reference,
                   "How can I find Montréal contacts?",
                   conversation,
                   locale
                 )

        assert_receive {:assistant_generated, _, _}

        browser =
          browser
          |> switch_browser_identity(&login(&1, c.admin))
          |> visit("/admin/assistant/activity/requests/#{second_reference}?locale=#{locale}")
          |> connected()
          |> assert_has("#assistant-review-approve")
          |> click_button("#assistant-review-approve", tr(locale, "Approve answer"))
          |> check(
            "#assistant-review-confirmed",
            tr(locale, "I reviewed the displayed question, answer and review results.")
          )

        Repo.update!(Ecto.Changeset.change(c.admin, superadmin: false))

        browser =
          browser
          |> click_button("#assistant-review-confirm", tr(locale, "Confirm approval"))
          |> assert_path("/")
          |> refute_has("#assistant-review-answer")
          |> capture(
            id,
            "Revoked access denies the pending confirmation",
            "A superadmin's already-open confirmation",
            "Revoke the role in the synthetic fixture; Confirm approval",
            "Fresh authorization redirects the revoked account and the second answer stays withheld."
          )

        assert {:ok, [_, _]} =
                 PhoenixAgentAssistant.History.read(
                   Assistant.store(),
                   c.admin.id,
                   conversation,
                   config[:audit_keys]
                 )

        refute_receive {:assistant_generated, _, _}
        success(id)
        browser
      end
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "ASSIST-INPUT-01-#{locale} approve held input then generate and review its frozen context",
           c do
        locale = unquote(locale)
        id = "ASSIST-INPUT-01-#{locale}"
        config = Application.fetch_env!(:pauseai_ca, :agent_assistant)
        assert {:ok, _} = Assistant.set_enabled(c.scope, true)
        assert {:ok, conversation} = Assistant.conversation(c.scope)

        assert {:ok, _} =
                 Assistant.run(
                   c.scope,
                   Ecto.UUID.generate(),
                   "Find local-group candidates",
                   conversation,
                   locale
                 )

        assert_receive {:assistant_generated, _, _}

        safety =
          Keyword.put(
            config[:safety],
            :jev,
            {AssistantFixtures.HeldInput, [api_key: "synthetic-review"]}
          )

        Application.put_env(:pauseai_ca, :agent_assistant, Keyword.put(config, :safety, safety))

        browser =
          c.conn
          |> login(c.admin)
          |> visit("/admin/contacts?locale=#{locale}")
          |> connected()
          |> click_button("#site-assistant-launcher", "Assistant")
          |> fill_in("#site-assistant-text", tr(locale, "Message"), with: "show me")
          |> click_button("#site-assistant-form button[type=submit]", tr(locale, "Send"))
          |> assert_has(".paa-error",
            text:
              tr(
                locale,
                "The automatic input review held your request before answer generation. Your message is retained."
              )
          )
          |> capture(
            id,
            "Input held with the original conversational context",
            "Contacts → Assistant",
            "Type show me; Send",
            "The input-review warning retains the message and links to its protected request."
          )

        refute_receive {:assistant_generated, _, _}

        evaluate(
          browser,
          "document.querySelector('.paa-error a').getAttribute('href')",
          fn path -> send(self(), {:input_review_path, path}) end
        )

        assert_receive {:input_review_path, path}
        reference = path |> URI.parse() |> Map.fetch!(:path) |> String.split("/") |> List.last()

        browser =
          browser
          |> click_link(".paa-error a", tr(locale, "Review details"))
          |> assert_has("#assistant-review-approve",
            text: tr(locale, "Approve request and generate answer")
          )
          |> capture(
            id,
            "The protected input has an approval action",
            "Input hold warning / Telegram",
            "Review details / Open protected request review",
            "The retained question, input scores, Approve request and generate answer, and Reject request are visible."
          )
          |> switch_browser_identity(&login(&1, c.other))
          |> visit(path)
          |> connected()
          |> click_button(
            "#assistant-review-approve",
            tr(locale, "Approve request and generate answer")
          )
          |> assert_has("#assistant-review-confirmation",
            text: tr(locale, "Approve this request and generate an answer?")
          )
          |> click_button("#assistant-review-confirm", tr(locale, "Confirm approval"))
          |> assert_has("#assistant-review-decision-error",
            text:
              tr(
                locale,
                "Confirm that you reviewed the displayed question and input review results."
              )
          )
          |> capture(
            id,
            "Confirm generation on the requester's credits",
            "Protected held input as another superadmin",
            "Approve request and generate answer",
            "The confirmation discloses the frozen context/model, fresh permissions/credits and mandatory output review."
          )
          |> check(
            "#assistant-review-confirmed",
            tr(locale, "I reviewed the displayed question and input review results.")
          )
          |> click_button("#assistant-review-confirm", tr(locale, "Confirm approval"))
          |> assert_has("#assistant-review-answer",
            text: "Use the contact filters to choose a city."
          )
          |> assert_has("#assistant-exchange-status",
            text: tr(locale, "The answer was released automatically."),
            exact: true
          )
          |> capture(
            id,
            "The generated answer passed output review",
            "Completed superadmin confirmation",
            "Confirm approval",
            "Exactly one fixture generation uses the frozen request. The result opens its continued request with normal output review."
          )

        assert_receive {:assistant_generated, generated, _}
        assert generated["text"] == "show me"
        assert Jason.encode!(generated["context"]) =~ "Find local-group candidates"
        assert {:ok, child} = PauseAiCa.Assistant.RequestReview.resume(c.other_scope, reference)
        assert child.status == :released
        refute_receive {:assistant_generated, _, _}

        browser =
          browser
          |> switch_browser_identity(&login(&1, c.admin))
          |> visit("/admin/contacts?locale=#{locale}")
          |> connected()
          |> click_button("#site-assistant-launcher", "Assistant")
          |> assert_has(".paa-message[data-role=user]", text: "show me")
          |> capture(
            id,
            "Answer available to the original requester",
            "Continued protected request",
            "Sign in as requester → Contacts → Assistant",
            "The original conversation contains the approved follow-up and its answer, without replaying generation."
          )

        second_reference = Ecto.UUID.generate()

        assert {:error, :input_safety_review_required} =
                 Assistant.run(
                   c.scope,
                   second_reference,
                   "Show Montréal candidates",
                   conversation,
                   locale
                 )

        browser =
          browser
          |> switch_browser_identity(&login(&1, c.other))
          |> visit("/admin/assistant/activity/requests/#{second_reference}?locale=#{locale}")
          |> connected()
          |> click_button(
            "#assistant-review-approve",
            tr(locale, "Approve request and generate answer")
          )
          |> check(
            "#assistant-review-confirmed",
            tr(locale, "I reviewed the displayed question and input review results.")
          )

        Repo.update!(Ecto.Changeset.change(c.other, superadmin: false))

        browser =
          browser
          |> click_button("#assistant-review-confirm", tr(locale, "Confirm approval"))
          |> assert_path("/")
          |> capture(
            id,
            "Revoked reviewer cannot generate",
            "Open input confirmation",
            "Revoke fixture superadmin; Confirm approval",
            "Fresh authorization denies the decision and no generation starts."
          )

        refute_receive {:assistant_generated, _, _}
        success(id)
        browser
      end
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "AI-INSTR-01-#{locale} private coaching draft, publish and ordinary role denial", c do
        locale = unquote(locale)
        id = "AI-INSTR-01-#{locale}"
        path = "/admin/assistant/instructions?locale=#{locale}"
        private_editor = "synthetic-private-allowlist@example.org"

        initial =
          "# SYNTHETIC INITIAL COACHING\n\nHelp synthetic organizers review local contacts."

        updated =
          "# SYNTHETIC REVISED COACHING\n\nExplain the next local review action in #{locale}."

        ordinary = user_fixture(%{email: "instructions-group-manager@example.org"})
        group = Repo.insert!(%PauseAiCa.Volunteers.Group{name: "Synthetic instructions review"})
        Repo.insert!(%PauseAiCa.Volunteers.Manager{user_id: ordinary.id, group_id: group.id})
        assert PauseAiCa.Volunteers.allowed?(Accounts.Scope.for_user(ordinary))
        refute PauseAiCa.Volunteers.superadmin?(Accounts.Scope.for_user(ordinary))

        flush_mail()

        Application.put_env(:pauseai_ca, :assistant_instruction_editors, [
          c.admin.email,
          private_editor
        ])

        assert {:ok, draft} = Instructions.save(c.scope, 0, initial)
        assert {:ok, published} = Instructions.publish(c.scope, draft.revision)
        binding = Assistant.configuration()[:instruction_binding]
        assert {:ok, %{source: ^initial}} = Instructions.effective()
        refute Store.enabled?(Assistant.store())

        browser =
          c.conn
          |> login(c.admin)
          |> visit("/#{locale}")
          |> assert_has("#admin-menu")
          |> PauseAiCaWeb.AtddNavigation.open_section("admin")
          |> capture(
            id,
            "Administrator navigation",
            "Synthetic account on the localized homepage",
            "Open Admin",
            "The normal website navigation exposes Assistant to the current synthetic superadmin."
          )
          |> click_link("#admin-menu a", tr(locale, "Assistant"), exact: true)
          |> connected()
          |> assert_has("#assistant-instructions-link",
            text: tr(locale, "Instructions"),
            exact: true
          )
          |> refute_has("body", text: private_editor)
          |> capture(
            id,
            "Restricted editor entry",
            "Localized homepage with Admin open",
            "Assistant",
            "Only the allowlisted synthetic superadmin sees the Instructions entry. The editor list is absent from the page."
          )
          |> click_link("#assistant-instructions-link", tr(locale, "Instructions"))
          |> connected()
          |> assert_has("#assistant-instruction-source-source", value: initial)
          |> capture(
            id,
            "Current synthetic instructions",
            "Assistant settings",
            "Instructions",
            "The editor shows the actual effective synthetic coaching. All fixture text is isolated from live instructions."
          )
          |> fill_in(
            "#assistant-instruction-source-source",
            tr(locale, "Application instructions · Markdown"),
            with: updated
          )
          |> assert_has("#assistant-instruction-status",
            text: tr(locale, "Unsaved changes"),
            exact: true
          )
          |> click_button("#assistant-instruction-save", tr(locale, "Save draft"))
          |> assert_has("#assistant-instruction-status",
            text: tr(locale, "Draft saved"),
            exact: true
          )

        assert {:ok, %{source: ^initial}} = Instructions.effective()
        assert Assistant.configuration()[:instruction_binding] == binding
        assert {:ok, saved} = Instructions.get(c.scope)
        assert saved.source == updated
        assert saved.revision == published.revision + 1

        browser =
          browser
          |> visit(path)
          |> connected()
          |> assert_has("#assistant-instruction-source-source", value: updated)
          |> capture(
            id,
            "Saved draft survives reload",
            "Instructions editor after Save draft",
            "Save draft; reload the Instructions URL",
            "The revised draft persists. The provider still uses the previously published fixture source and binding."
          )
          |> click_button(
            "#assistant-instruction-publish",
            tr(locale, "Publish saved instructions")
          )
          |> assert_has("#assistant-instruction-status",
            text: tr(locale, "Instructions published"),
            exact: true
          )
          |> PhoenixTest.Playwright.click("#assistant-instruction-history > summary")
          |> assert_has("#assistant-instruction-history article p", text: c.admin.id)
          |> capture(
            id,
            "Published instructions and attributed history",
            "Reloaded saved draft",
            "Publish saved instructions; open Revision history",
            "Explicit publication changes the effective source and revision/hash binding. The private revision history attributes Save and Publish to the signed-in fixture account."
          )

        assert {:ok, effective} = Instructions.effective()
        assert effective.source == updated
        assert effective.revision == saved.revision + 1
        refute Assistant.configuration()[:instruction_binding] == binding
        assert {_provider, options} = Assistant.configuration()[:provider]
        assert options[:instructions] == updated
        assert {:ok, history} = Instructions.history(c.scope)
        assert Enum.map(history, & &1.action) == ["publish", "save", "publish", "save"]
        assert Enum.all?(history, &(&1.editor_id == c.admin.id))

        browser =
          browser
          |> switch_browser_identity(&login(&1, c.other))
          |> visit("/admin/assistant?locale=#{locale}")
          |> connected()
          |> refute_has("#assistant-instructions-link")
          |> refute_has("body", text: private_editor)
          |> refute_has("body", text: "SYNTHETIC REVISED COACHING")
          |> capture(
            id,
            "Other superadmin settings",
            "Allowlisted superadmin's published fixture instructions",
            "Sign in as the other synthetic superadmin; open Assistant",
            "Assistant settings retain ordinary administration controls while the restricted Instructions link, editor list and coaching are absent."
          )
          |> denied_instruction_request(path)
          |> visit(path)
          |> assert_has("body", text: "Not found", exact: true)
          |> capture(
            id,
            "Other superadmin denied",
            "Other synthetic superadmin on Assistant settings without Instructions",
            "Open the restricted Instructions URL directly",
            "The real request returns 404 with no-store. The page exposes no instructions or editor list."
          )

        browser =
          browser
          |> switch_browser_identity(&login(&1, ordinary))
          |> visit("/#{locale}")
          |> assert_has("#account-menu")
          |> refute_has("#assistant-instructions-link")
          |> refute_has("body", text: private_editor)
          |> denied_instruction_request(path)
          |> visit(path)
          |> assert_has("body", text: "Not found", exact: true)
          |> capture(
            id,
            "Group manager denied",
            "Synthetic group manager on the localized homepage",
            "Open the restricted Instructions URL directly",
            "An ordinary organizer's group-management rights grant no access to the private instructions editor."
          )

        refute Store.enabled?(Assistant.store())
        refute_receive {:assistant_generated, _, _}
        refute_received {:email, _}
        success(id)
        browser
      end
    end

    defp reconnect_assistant(browser) do
      evaluate(
        browser,
        """
        new Promise((resolve, reject) => {
          window.liveSocket.connect();
          const deadline = Date.now() + 5000;
          const timer = setInterval(() => {
            const owner = document.querySelector('#site-assistant')?.closest('[data-phx-session]');
            const joined = owner && window.liveSocket.getSocket().channels.some(channel =>
              channel.topic === `lv:${owner.id}` && channel.state === 'joined');
            const assistant = document.querySelector('#site-assistant');
            const stored = sessionStorage.getItem('paa:draft:' + assistant?.dataset.draftKey);
            const expected = stored ? JSON.parse(stored).text : null;
            const restored = expected === null || assistant?.querySelector('textarea')?.value === expected;
            if (joined && owner.classList.contains('phx-connected') && restored) {
              clearInterval(timer); resolve(true);
            }
            else if (Date.now() > deadline) { clearInterval(timer); reject(new Error('Assistant channel did not rejoin')); }
          }, 20);
        })
        """,
        &assert(&1)
      )
    end

    defp open_assistant_if_closed(browser) do
      evaluate(
        browser,
        "document.querySelector('#site-assistant-dialog').open",
        &Process.put(:assistant_dialog_open, &1)
      )

      if Process.get(:assistant_dialog_open),
        do: browser,
        else: click_button(browser, "#site-assistant-launcher", "Assistant")
    end

    defp denied_instruction_request(browser, path) do
      evaluate(
        browser,
        """
        (async () => {
          const response = await fetch(#{Jason.encode!(path)});
          return {status: response.status, cache: response.headers.get('cache-control'), text: await response.text()};
        })()
        """,
        fn response ->
          assert response == %{
                   "status" => 404,
                   "cache" => "private, no-store",
                   "text" => "Not found"
                 }
        end
      )

      browser
    end

    defp set_limit(browser, email, limit, locale) do
      browser
      |> select("#assistant-token-limit-form select", tr(locale, "Account"),
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

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-ASSIST-CREDIT-01-#{locale} credit status is beside enable and warned before typing",
           c do
        locale = unquote(locale)
        id = "CRM-ASSIST-CREDIT-01-#{locale}"
        config = AssistantFixtures.configuration(self()) |> Keyword.put(:daily_limit_micros, 1000)
        Application.put_env(:pauseai_ca, :agent_assistant, config)

        assert {:ok, _} = Assistant.set_enabled(c.scope, true)

        assert {:ok, _} =
                 Store.reserve(
                   Assistant.store(),
                   c.admin.id,
                   %{
                     request_id: Ecto.UUID.generate(),
                     digest: String.duplicate("a", 64),
                     mode: "fast",
                     model: "haiku-fixture",
                     max_output_tokens: 10
                   },
                   config[:audit_keys],
                   max_cost_micros: 1000,
                   daily_limit_micros: 1000,
                   max_tokens: 100,
                   daily_token_limit: 100_000,
                   max_daily_token_limit: 1_000_000
                 )

        label = if locale == "fr", do: "Crédit insuffisant", else: "Insufficient credit"
        warning = if locale == "fr", do: "Le crédit disponible", else: "Available credit"

        browser =
          c.conn
          |> login(c.admin)
          |> visit("/admin/assistant?locale=#{locale}")
          |> connected()
          |> assert_has("#assistant-toggle-controls #assistant-disable")
          |> assert_has("#assistant-toggle-controls #assistant-availability", text: label)
          |> capture(
            id,
            "Account availability beside the enable control",
            "Assistant settings",
            "Open Assistant settings",
            "Enabled state and insufficient account credit appear together."
          )
          |> visit("/admin/contacts?locale=#{locale}")
          |> connected()
          |> click_button("#site-assistant-launcher", "Assistant")
          |> assert_has("#site-assistant-error", text: warning)
          |> assert_has("#site-assistant-error a[href='/admin/assistant?locale=#{locale}']")
          |> evaluate(
            "getComputedStyle(document.querySelector('#site-assistant-error a')).textDecorationLine.includes('underline')",
            &assert(&1)
          )
          |> assert_has("#site-assistant-form button[type=submit][disabled]")
          |> fill_in("#site-assistant-text", "Message", with: "Retain this draft")
          |> assert_has("#site-assistant-text", value: "Retain this draft")
          |> capture(
            id,
            "Credit warning before submission with editable retained draft",
            "Contacts",
            "Assistant then type a draft",
            "Insufficient credit is explained before typing, Send is disabled, and the draft remains editable."
          )

        settings_label =
          if locale == "fr", do: "Paramètres de l’assistant", else: "Assistant settings"

        browser =
          browser
          |> click_link("#site-assistant-error a", settings_label)
          |> connected()
          |> assert_has("#assistant-toggle-controls #assistant-availability", text: label)

        refute_receive {:assistant_generated, _, _}
        success(id)
        browser
      end

      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-ASSIST-LAUNCHER-01-#{locale} enabled assistant leaves footer links accessible",
           c do
        locale = unquote(locale)
        id = "CRM-ASSIST-LAUNCHER-01-#{locale}"
        assert {:ok, _} = Assistant.set_enabled(c.scope, true)

        browser =
          c.conn
          |> login(c.admin)
          |> visit("/#{locale}")
          |> assert_has(".phx-connected #site-assistant-launcher svg[aria-hidden=true]")
          |> assert_has("#site-assistant-launcher-help",
            text:
              tr(
                locale,
                "Drag this button to move it, or use the arrow keys when focused. Home resets its position."
              )
          )
          |> evaluate(
            """
            new Promise(resolve => {
              document.querySelector('#site-footer').scrollIntoView({block: 'end', behavior: 'instant'});
              requestAnimationFrame(() => requestAnimationFrame(() => {
                resolve([...document.querySelectorAll('#site-footer a[target="_blank"]')].every(link => {
                  const box = link.getBoundingClientRect();
                  return document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)?.closest('a') === link;
                }));
              }));
            })
            """,
            &assert(&1)
          )
          |> screenshot("#{id}-footer-viewport.png", full_page: false)
          |> capture(
            id,
            "Assistant icon and reachable social links",
            "Homepage footer",
            "Scroll to the footer with assistant enabled",
            "Social links remain reachable before moving the assistant; the launcher exposes localized movement help."
          )
          |> click_button("#site-assistant-launcher", "Assistant")
          |> assert_has("#site-assistant-dialog[open]")

        refute_receive {:assistant_generated, _, _}
        success(id)
        browser
      end

      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-ASSIST-SOCIAL-01-#{locale} public footer links the three supplied Canadian accounts",
           c do
        locale = unquote(locale)
        id = "CRM-ASSIST-SOCIAL-01-#{locale}"
        home = if locale == "fr", do: "/fr", else: "/en"
        privacy = if locale == "fr", do: "/fr/confidentialite", else: "/en/privacy"
        label = if locale == "fr", do: "Confidentialité", else: "Privacy"

        browser =
          c.conn
          |> visit(home)
          |> click_link("footer a[href='#{privacy}']", label)
          |> assert_has(
            "footer nav a[href='https://www.instagram.com/pauseaicanada/'][target='_blank']",
            text: "Instagram"
          )
          |> assert_has(
            "footer nav a[href='https://bsky.app/profile/pauseaicanada.bsky.social'][target='_blank']",
            text: "Bluesky"
          )
          |> assert_has("footer nav a[href='https://x.com/pauseaicanada'][target='_blank']",
            text: "X"
          )
          |> capture(
            id,
            "Official Canadian social accounts in the footer",
            "Public homepage",
            "Footer Privacy",
            "Instagram, Bluesky and X use Olivier's supplied Canadian account URLs in both language editions."
          )

        success(id)
        browser
      end
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
