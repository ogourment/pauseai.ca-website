defmodule PauseAiCaWeb.AssistantLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Assistant, Repo}
  alias PhoenixAgentAssistant.Store

  setup do
    previous = Application.get_env(:pauseai_ca, :agent_assistant)
    previous_build = System.get_env("PAUSEAI_CA_RELEASE_ID")
    System.put_env("PAUSEAI_CA_RELEASE_ID", "assistant-synthetic-fixture")

    Application.put_env(
      :pauseai_ca,
      :agent_assistant,
      PauseAiCa.AssistantFixtures.configuration(self())
    )

    admin =
      user_fixture(%{email: "assistant-admin@example.org"})
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()

    other_admin =
      user_fixture(%{email: "assistant-other-admin@example.org"})
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()

    member = user_fixture(%{email: "assistant-member@example.org"})
    scope = Accounts.Scope.for_user(admin)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pauseai_ca, :agent_assistant, previous),
        else: Application.delete_env(:pauseai_ca, :agent_assistant)

      if previous_build,
        do: System.put_env("PAUSEAI_CA_RELEASE_ID", previous_build),
        else: System.delete_env("PAUSEAI_CA_RELEASE_ID")
    end)

    %{admin: admin, scope: scope, member: member, other_admin: other_admin}
  end

  test "OFF has no assistant launcher; an administrator explicitly enables it", c do
    conn = log_in_user(c.conn, c.admin)
    {:ok, view, html} = live(conn, "/admin/assistant?locale=en")
    assert html =~ "Token usage and limits"
    refute html =~ "id=\"site-assistant-launcher\""
    assert has_element?(view, "#assistant-enable:not([disabled])")
    view |> element("#assistant-enable") |> render_click()
    assert Store.enabled?(Assistant.store())
    assert has_element?(view, "#assistant-disable")
    refute_receive {:assistant_generated, _, _}
  end

  test "members and unconfirmed accounts cannot enable or use the assistant", c do
    conn = log_in_user(c.conn, c.member)
    assert conn |> get("/admin/assistant?locale=en") |> response(403) == "superadmin required"
    refute Assistant.visible?(Accounts.Scope.for_user(c.member))
    assert {:error, :not_ready} = Assistant.set_enabled(Accounts.Scope.for_user(c.member), true)
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    refute Assistant.visible?(Accounts.Scope.for_user(c.member))

    unconfirmed =
      unconfirmed_user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

    refute Assistant.eligible?(Accounts.Scope.for_user(unconfirmed))
    refute_receive {:assistant_generated, _, _}
  end

  test "zero default and explicit zero allocations hide the launcher while a positive override shows it",
       c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    config = Application.get_env(:pauseai_ca, :agent_assistant)
    Application.put_env(:pauseai_ca, :agent_assistant, Keyword.put(config, :daily_token_limit, 0))
    other_scope = Accounts.Scope.for_user(c.other_admin)
    refute Assistant.launcher_visible?(c.scope)
    refute Assistant.launcher_visible?(other_scope)

    token = Accounts.generate_user_session_token(c.admin)

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive, session: %{"user_token" => token})

    refute has_element?(view, "#site-assistant-launcher")

    assert {:ok, _} = Assistant.set_token_limit(c.scope, c.admin.id, 100_000)
    send(view.pid, :refresh_access)
    assert Assistant.launcher_visible?(c.scope)
    assert has_element?(view, "#site-assistant-launcher")
    refute Assistant.launcher_visible?(other_scope)

    assert {:ok, _} = Assistant.set_token_limit(c.scope, c.admin.id, 0)
    send(view.pid, :refresh_access)
    refute Assistant.launcher_visible?(c.scope)
    refute has_element?(view, "#site-assistant-launcher")
    render_click(view, "assistant-toggle")
    refute has_element?(view, "#site-assistant-launcher")
    refute_receive {:assistant_generated, _, _}
    assert Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count) == 0
  end

  test "an exhausted positive allocation keeps the launcher without admitting model calls", c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    assert {:ok, _} = Assistant.set_token_limit(c.scope, c.admin.id, 100)
    config = Assistant.configuration()

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
               daily_limit_micros: config[:daily_limit_micros],
               max_tokens: 100,
               daily_token_limit: config[:daily_token_limit],
               max_daily_token_limit: config[:max_daily_token_limit]
             )

    assert {:ok, %{limit: 100, remaining_tokens: 0}} = Assistant.token_usage(c.scope)
    assert Assistant.launcher_visible?(c.scope)
    token = Accounts.generate_user_session_token(c.admin)

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive, session: %{"user_token" => token})

    assert has_element?(view, "#site-assistant-launcher")
    assert has_element?(view, "#site-assistant button[type=submit][disabled]")
    refute_receive {:assistant_generated, _, _}
  end

  test "a stale funded scope loses its launcher when the administrator role is revoked", c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    assert {:ok, _} = Assistant.set_token_limit(c.scope, c.admin.id, 100_000)
    token = Accounts.generate_user_session_token(c.admin)

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive, session: %{"user_token" => token})

    assert has_element?(view, "#site-assistant-launcher")

    c.admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    send(view.pid, :refresh_access)
    refute Assistant.launcher_visible?(c.scope)
    refute has_element?(view, "#site-assistant-launcher")
    render_submit(view, "assistant-submit", %{"assistant" => %{"text" => "Find contacts"}})
    refute_receive {:assistant_generated, _, _}
    assert Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count) == 0
  end

  test "missing readiness blocks activation even through a forged event", c do
    config = Application.get_env(:pauseai_ca, :agent_assistant) |> Keyword.delete(:safety)
    Application.put_env(:pauseai_ca, :agent_assistant, config)
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")
    assert has_element?(view, "#assistant-enable[disabled]")
    render_click(view, "enable")
    refute Store.enabled?(Assistant.store())
    refute_receive {:assistant_generated, _, _}
  end

  test "old proof booleans cannot activate a missing operational connection", c do
    config =
      Application.get_env(:pauseai_ca, :agent_assistant)
      |> Keyword.delete(:operations_adapter)
      |> Keyword.put(:audit_anchor_verified, true)
      |> Keyword.put(:alert_delivery_verified, true)
      |> Keyword.put(:price_policy_verified, true)

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    assert :audit_anchor in Assistant.readiness()
    assert :operator_alerts in Assistant.readiness()
    assert {:error, :not_ready} = Assistant.set_enabled(c.scope, true)
    refute Store.enabled?(Assistant.store())
  end

  test "readiness refresh enables the control without reloading the page", c do
    config =
      Application.get_env(:pauseai_ca, :agent_assistant)
      |> Keyword.put(
        :operations_adapter,
        {PauseAiCa.AssistantFixtures.Operations, [ready: false]}
      )

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")
    assert has_element?(view, "#assistant-enable[disabled]")

    config =
      Keyword.put(
        config,
        :operations_adapter,
        {PauseAiCa.AssistantFixtures.Operations, [ready: true]}
      )

    Application.put_env(:pauseai_ca, :agent_assistant, config)

    Phoenix.PubSub.broadcast(
      PauseAiCa.PubSub,
      "agent_assistant:settings",
      :assistant_settings_changed
    )

    assert has_element?(view, "#assistant-enable:not([disabled])")
    refute_receive {:assistant_generated, _, _}
  end

  test "periodic cached refresh recovers a missed notification while preserving configured On",
       c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    config = Application.get_env(:pauseai_ca, :agent_assistant)

    unavailable =
      Keyword.put(
        config,
        :operations_adapter,
        {PauseAiCa.AssistantFixtures.Operations, [ready: false]}
      )

    Application.put_env(:pauseai_ca, :agent_assistant, unavailable)
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")
    assert has_element?(view, "#assistant-status", "On")
    assert has_element?(view, "#assistant-readiness h2", "Assistant temporarily unavailable")

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    send(view.pid, :refresh_readiness)
    refute has_element?(view, "#assistant-readiness")
    assert has_element?(view, "#assistant-status", "On")
    refute_receive {:assistant_generated, _, _}
  end

  test "periodic cached refresh reflects expired evidence and displays UTC diagnostics", c do
    key = {PauseAiCa.Assistant.Operations, :status}
    previous = :persistent_term.get(key, :missing)

    on_exit(fn ->
      if previous == :missing,
        do: :persistent_term.erase(key),
        else: :persistent_term.put(key, previous)
    end)

    config = Application.get_env(:pauseai_ca, :agent_assistant)
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")
    config = Keyword.delete(config, :operations_adapter)
    Application.put_env(:pauseai_ca, :agent_assistant, config)

    :persistent_term.put(key, %{
      fingerprint: PauseAiCa.Assistant.Operations.fingerprint(Assistant.configuration()),
      checked_at: System.monotonic_time(:millisecond) - 65_001,
      checked_at_utc: ~U[2026-11-09 22:00:00Z],
      last_success_at_utc: ~U[2026-11-09 21:59:30Z],
      audit_anchor: true,
      alerts: true
    })

    send(view.pid, :refresh_readiness)
    assert has_element?(view, "#assistant-enable[disabled]")
    assert has_element?(view, "#assistant-operational-check", "Current verification required")

    assert has_element?(
             view,
             "#assistant-operational-check time[datetime='2026-11-09T22:00:00Z']"
           )

    refute_receive {:assistant_generated, _, _}
  end

  test "per-admin token limit is editable without granting access or resetting usage", c do
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")

    view
    |> form("#assistant-token-limit-form",
      assistant_settings: %{actor_id: c.other_admin.id, limit: "25000"}
    )
    |> render_submit()

    assert {:ok, %{limit: 25_000}} = Assistant.token_usage(Accounts.Scope.for_user(c.other_admin))
    assert {:ok, %{limit: 100_000}} = Assistant.token_usage(c.scope)
    assert {:error, :forbidden} = Assistant.set_token_limit(c.scope, c.member.id, 100_000)

    assert {:error, :forbidden} =
             Assistant.set_token_limit(Accounts.Scope.for_user(c.member), c.admin.id, 0)
  end

  test "lowering the infrastructure ceiling clamps saved quotas and admin summaries", c do
    assert {:ok, _} = Assistant.set_token_limit(c.scope, c.other_admin.id, 25_000)
    config = Application.get_env(:pauseai_ca, :agent_assistant)

    Application.put_env(
      :pauseai_ca,
      :agent_assistant,
      Keyword.put(config, :max_daily_token_limit, 20_000)
    )

    assert Assistant.readiness() == []
    assert {:ok, %{limit: 20_000}} = Assistant.token_usage(Accounts.Scope.for_user(c.other_admin))

    assert %{usage: {:ok, %{limit: 20_000}}} =
             Enum.find(Assistant.admin_usage(c.scope), &(&1.id == c.other_admin.id))

    assert {:error, :forbidden} = Assistant.set_token_limit(c.scope, c.other_admin.id, 20_001)
    assert {:ok, _} = Assistant.set_token_limit(c.scope, c.other_admin.id, 0)
    assert {:ok, %{limit: 0}} = Assistant.token_usage(Accounts.Scope.for_user(c.other_admin))
  end

  test "confirmed admin mode and released conversation persist; blocked requests stay private",
       c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    assert {:ok, reference} = Assistant.conversation(c.scope)
    assert {:ok, _} = Assistant.set_mode(c.scope, "high")

    assert {:ok, reply} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "Find contacts by city", reference)

    assert reply.model == "opus-fixture"
    keys = Assistant.configuration()[:audit_keys]

    audited =
      Repo.all(PhoenixAgentAssistant.Store.AuditEntry)
      |> Enum.map(fn row ->
        {:ok, event} =
          PhoenixAgentAssistant.Audit.open(
            row.envelope,
            row.stream_id,
            row.previous,
            row.sequence,
            keys
          )

        event
      end)

    assert Enum.any?(audited, fn event ->
             event["kind"] == "request" and
               event["runtime_policy"]["bindings"]["claude"]["project_ref"] == "synthetic-account" and
               event["runtime_policy"]["max_daily_token_limit"] == 1_000_000
           end)

    assert_receive {:assistant_generated, request, %{mode: "high"}}
    assert request["context"]["app_version"] == to_string(Application.spec(:pauseai_ca, :vsn))
    assert request["context"]["features"] |> hd() |> Map.fetch!("status") == "available"
    assert {:ok, [%{role: "user"}, %{role: "assistant"}]} = Assistant.history(c.scope, reference)

    assert {:ok, "high"} =
             Assistant.mode(Accounts.Scope.for_user(Repo.get!(Accounts.User, c.admin.id)))

    assert {:ok, %{reported_input: 70, reported_output: 10, charged_tokens: 80}} =
             Assistant.token_usage(c.scope)

    assert {:error, :unavailable} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "synthetic blocked request", reference)

    assert {:ok, [_, _]} = Assistant.history(c.scope, reference)
    assert {:ok, [alert]} = Store.pending_alerts(Assistant.store())
    assert alert.reason_code == "safety_blocked"
    assert {:ok, []} = Assistant.history(Accounts.Scope.for_user(c.other_admin), reference)
  end

  test "zero quota and role revocation prevent further model requests", c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    assert {:ok, reference} = Assistant.conversation(c.scope)
    assert {:ok, _} = Assistant.set_token_limit(c.scope, c.admin.id, 0)

    assert {:error, :unavailable} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "Find contacts", reference)

    refute_receive {:assistant_generated, _, _}
    c.admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    refute Assistant.visible?(c.scope)

    assert {:error, :unavailable} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "Find contacts", reference)
  end

  test "a malformed quota form stays connected and makes no quota change", c do
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")

    render_submit(view, "token-limit", %{
      "assistant_settings" => %{"actor_id" => c.admin.id, "limit" => %{}}
    })

    assert has_element?(view, "#assistant-token-limit-form")
    assert {:ok, %{limit: 100_000}} = Assistant.token_usage(c.scope)
  end

  test "the floating async request keeps the website language", c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    token = Accounts.generate_user_session_token(c.admin)

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive,
        session: %{"user_token" => token, "site_locale" => "fr"}
      )

    render_submit(view, "assistant-submit", %{
      "assistant" => %{"text" => "Comment trouver les contacts?"}
    })

    # Observe the provider boundary before waiting for billing/audit persistence.
    # This verifies the request locale without imposing the helper's incidental
    # 100ms completion deadline on the entire database-backed async workflow.
    assert_receive {:assistant_generated, request, _}, 1_000
    assert request["context"]["locale"] == "fr"
    render_async(view, 1_000)
  end

  test "mode changes retain the just-typed draft before its debounce event", c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    token = Accounts.generate_user_session_token(c.admin)

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive, session: %{"user_token" => token})

    render_change(view, "assistant-mode", %{
      "mode" => "high",
      "assistant" => %{"text" => "Draft typed immediately"}
    })

    assert render(view) =~ "Draft typed immediately"
    assert {:ok, "high"} = Assistant.mode(c.scope)
    render_click(view, "assistant-new")
    assert {:ok, "high"} = Assistant.mode(c.scope)
    assert has_element?(view, "select option[value='high'][selected]")
  end

  test "transient readiness keeps the enabled launcher and draft but blocks a forged send", c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    token = Accounts.generate_user_session_token(c.admin)

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive, session: %{"user_token" => token})

    render_click(view, "assistant-toggle")
    render_change(view, "assistant-draft", %{"assistant" => %{"text" => "Keep this draft"}})
    original = Assistant.configuration()

    Application.put_env(
      :pauseai_ca,
      :agent_assistant,
      Keyword.put(
        original,
        :operations_adapter,
        {PauseAiCa.AssistantFixtures.Operations, [ready: false]}
      )
    )

    send(view.pid, :refresh_access)
    assert render(view) =~ "Keep this draft"
    assert has_element?(view, "#site-assistant[data-open='true']")
    assert has_element?(view, "#site-assistant-launcher")
    assert has_element?(view, "#site-assistant button[type=submit][disabled]")
    assert render(view) =~ "temporarily unavailable"
    assert Assistant.launcher_visible?(c.scope)
    refute Assistant.visible?(c.scope)
    refute Assistant.launcher_visible?(Accounts.Scope.for_user(c.member))
    render_submit(view, "assistant-submit", %{"assistant" => %{"text" => "Keep this draft"}})
    refute_receive {:assistant_generated, _, _}
    assert Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count) == 0
    Application.put_env(:pauseai_ca, :agent_assistant, original)
    send(view.pid, :refresh_access)
    assert has_element?(view, "#site-assistant button[type=submit]:not([disabled])")
    assert render(view) =~ "Keep this draft"
    assert {:ok, _} = Assistant.set_enabled(c.scope, false)
    send(view.pid, :refresh_access)
    refute has_element?(view, "#site-assistant-launcher")
  end

  test "positive money remaining below the turn reservation disables Send without hiding tokens",
       c do
    config = Assistant.configuration() |> Keyword.put(:daily_limit_micros, 1500)
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
               daily_limit_micros: 1500,
               max_tokens: 100,
               daily_token_limit: 100_000,
               max_daily_token_limit: 1_000_000
             )

    assert {:ok, usage} = Assistant.token_usage(c.scope)
    assert usage.remaining_tokens > 0
    assert usage.remaining_cost_micros == 500
    assert usage.max_turn_cost_micros == 1000
    token = Accounts.generate_user_session_token(c.admin)

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive,
        session: %{"user_token" => token, "site_locale" => "fr"}
      )

    assert has_element?(view, "#site-assistant-launcher")
    assert has_element?(view, "#site-assistant button[type=submit][disabled]")
    assert render(view) =~ "0,0005"
    assert render(view) =~ "00:00 UTC"

    render_submit(view, "assistant-submit", %{"assistant" => %{"text" => "Retained budget draft"}})

    assert render(view) =~ "Retained budget draft"
    assert Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count) == 1
    refute_receive {:assistant_generated, _, _}
  end

  test "an oversized current message gives a useful limit error and remains editable", c do
    config =
      Application.get_env(:pauseai_ca, :agent_assistant)
      |> Keyword.put(:max_turn_tokens, 16_384)
      |> Keyword.put(:max_output_tokens, 4096)

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    token = Accounts.generate_user_session_token(c.admin)

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive,
        session: %{"user_token" => token, "site_locale" => "en"}
      )

    text = String.duplicate("x", 15_000)
    render_submit(view, "assistant-submit", %{"assistant" => %{"text" => text}})
    render_async(view, 1_000)
    assert render(view) =~ "This request exceeds the assistant’s per-request limit."
    assert has_element?(view, "#site-assistant-text", text)
    refute_receive {:assistant_generated, _, _}
    assert Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count) == 0
  end
end
