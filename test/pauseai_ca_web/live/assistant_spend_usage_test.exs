defmodule PauseAiCaWeb.AssistantSpendUsageTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Assistant, AssistantFixtures, Repo}
  alias PauseAiCa.Assistant.SpendTracking
  alias PhoenixAgentAssistant.Store

  setup do
    previous = Application.fetch_env(:pauseai_ca, :agent_assistant)
    config = AssistantFixtures.configuration(self())
    Application.put_env(:pauseai_ca, :agent_assistant, config)

    admin =
      user_fixture(%{email: "spend-admin@example.org"})
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()

    other =
      user_fixture(%{email: "spend-former@example.org"})
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()

    member = user_fixture(%{email: "spend-member@example.org"})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pauseai_ca, :agent_assistant, value)
        :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
      end
    end)

    %{
      admin: admin,
      other: other,
      member: member,
      scope: Accounts.Scope.for_user(admin),
      config: config
    }
  end

  defp tracked(config) do
    config
    |> Keyword.put(:stage_tracking, :required)
    |> Keyword.put(
      :provider,
      {PhoenixAgentAssistant.OpenRouter,
       [api_key: "SYNTHETIC-NOT-USED", provider: "fixture-provider"]}
    )
    |> Keyword.put(:safety,
      moderation: {PhoenixAgentAssistant.Safety.OpenAIModeration, [model: "moderation-fixture"]},
      jev: {PhoenixAgentAssistant.Safety.Jev, [model: "jev-fixture"]}
    )
  end

  defp reserve(actor, config) do
    assert {:ok, _} =
             Store.set_enabled(
               Assistant.store(),
               actor,
               true,
               Ecto.UUID.generate(),
               config[:audit_keys]
             )

    reservation = %{
      request_id: Ecto.UUID.generate(),
      digest: String.duplicate("b", 64),
      mode: "fast",
      model: "haiku-fixture",
      max_output_tokens: config[:max_output_tokens],
      max_tokens: 4096,
      max_cost_micros: config[:max_turn_cost_micros]
    }

    assert {:ok, ticket} = SpendTracking.reserve(Assistant.store(), actor, reservation, config)
    ticket
  end

  test "legacy display labels only reservations, not actual spend or an inferred credit balance",
       c do
    {:ok, view, html} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")
    assert html =~ "USD service value"
    assert html =~ "cash paid after credits"
    assert has_element?(view, "#assistant-cost-#{c.admin.id}", "Reserved limit: USD 0.000000")

    assert has_element?(
             view,
             "#assistant-cost-#{c.admin.id}",
             "Settled service value unavailable"
           )

    refute has_element?(view, "#assistant-cost-#{c.admin.id}", "Settled value:")

    assert {:error, :forbidden} =
             Assistant.spend_usage(Accounts.Scope.for_user(c.member), c.admin.id)

    refute_receive {:assistant_generated, _, _}
  end

  test "planned required stages display unknown holds, never zero settled usage", c do
    config = tracked(c.config)
    Application.put_env(:pauseai_ca, :agent_assistant, config)
    reserve(c.admin.id, config)
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")
    assert has_element?(view, "#assistant-cost-#{c.admin.id}", "No settled value yet")
    assert has_element?(view, "#assistant-cost-#{c.admin.id}", "Unknown hold: USD 0.001000")
    refute has_element?(view, "#assistant-cost-#{c.admin.id}", "Settled value: USD 0.000000")
  end

  test "subcent provider value and overlapping estimate coverage remain separate in compact details EN/FR",
       c do
    config = tracked(c.config)
    Application.put_env(:pauseai_ca, :agent_assistant, config)
    ticket = reserve(c.admin.id, config)

    assert :ok =
             SpendTracking.observe(
               Assistant.store(),
               c.admin.id,
               ticket,
               "generation",
               %{"state" => "started", "usage" => nil, "billing" => nil},
               config
             )

    assert :ok =
             SpendTracking.observe(
               Assistant.store(),
               c.admin.id,
               ticket,
               "generation",
               %{
                 "state" => "reported",
                 "usage" => %{"input_tokens" => 3, "output_tokens" => 4},
                 "billing" => %{
                   "provider" => "openrouter",
                   "reported_cost_micros" => 7,
                   "cost_basis" => "provider_reported"
                 }
               },
               config
             )

    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")
    assert has_element?(view, "#assistant-cost-#{c.admin.id}", "Settled value: USD 0.000007")
    assert has_element?(view, "#assistant-cost-#{c.admin.id}", "Unknown hold: USD 0.000002")

    assert has_element?(
             view,
             "#assistant-cost-#{c.admin.id} details",
             "Configured estimate: USD 0.000002 (1 stage)"
           )

    assert has_element?(
             view,
             "#assistant-cost-#{c.admin.id} details",
             "Provider report: USD 0.000007 (1 stage)"
           )

    {:ok, french, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=fr")
    assert has_element?(french, "#assistant-cost-#{c.admin.id}", "Valeur établie : USD 0,000007")

    assert has_element?(
             french,
             "#assistant-cost-#{c.admin.id}",
             "Réserve à confirmer : USD 0,000002"
           )
  end

  test "demoted and missing accounts keep attributable daily costs outside current-admin selector",
       c do
    config = tracked(c.config)
    Application.put_env(:pauseai_ca, :agent_assistant, config)
    reserve(c.other.id, config)
    missing = "missing-account-" <> Ecto.UUID.generate()
    reserve(missing, config)
    c.other |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    rows = Assistant.admin_usage(c.scope)

    assert %{current_admin: false, spend: {:ok, %{conservative_accounted_micros: 1000}}} =
             Enum.find(rows, &(&1.id == c.other.id))

    assert %{
             current_admin: false,
             email: nil,
             spend: {:ok, %{conservative_accounted_micros: 1000}}
           } = Enum.find(rows, &(&1.id == missing))

    {:ok, view, html} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")
    assert html =~ "spend-former@example.org" and html =~ "Former admin"
    assert html =~ missing and html =~ "Unavailable account"
    refute has_element?(view, "#assistant-admin-selector option[value='#{c.other.id}']")
    refute has_element?(view, "#assistant-admin-selector option[value='#{missing}']")
  end

  test "unverifiable observations display unavailable rather than silently replacing costs with zero",
       c do
    config = tracked(c.config)
    reserve(c.admin.id, config)

    invalid =
      Keyword.put(config, :audit_keys, %{
        config[:audit_keys]
        | encryption: :crypto.strong_rand_bytes(32)
      })

    Application.put_env(:pauseai_ca, :agent_assistant, invalid)
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=en")
    assert has_element?(view, "#assistant-cost-#{c.admin.id}", "Unavailable")
    refute has_element?(view, "#assistant-cost-#{c.admin.id}", "USD 0.000000")
  end
end
