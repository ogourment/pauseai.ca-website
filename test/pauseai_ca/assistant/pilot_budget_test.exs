defmodule PauseAiCa.Assistant.PilotBudgetTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Assistant, AssistantFixtures, Repo}
  alias PhoenixAgentAssistant.Store

  setup do
    previous = Application.fetch_env(:pauseai_ca, :agent_assistant)
    previous_build = System.get_env("PAUSEAI_CA_RELEASE_ID")
    System.put_env("PAUSEAI_CA_RELEASE_ID", "assistant-synthetic-fixture")
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)

    config =
      AssistantFixtures.configuration(self())
      |> Keyword.put(:stage_tracking, :required)
      |> Keyword.put(
        :provider,
        {PhoenixAgentAssistant.OpenRouter, [api_key: "SYNTHETIC-NOT-USED", provider: "fixture"]}
      )
      |> Keyword.put(:safety,
        moderation:
          {PhoenixAgentAssistant.Safety.OpenAIModeration,
           [api_key: "SYNTHETIC-NOT-USED", model: "moderation-fixture"]},
        jev:
          {PhoenixAgentAssistant.Safety.Jev,
           [api_key: "SYNTHETIC-NOT-USED", model: "jev-fixture"]}
      )
      |> Keyword.put(:pilot_budget, %{
        currency: "USD",
        limit_micros: 2000,
        starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    Application.put_env(:pauseai_ca, :agent_assistant, config)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pauseai_ca, :agent_assistant, value)
        :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
      end

      if previous_build,
        do: System.put_env("PAUSEAI_CA_RELEASE_ID", previous_build),
        else: System.delete_env("PAUSEAI_CA_RELEASE_ID")
    end)

    %{admin: admin, scope: scope, config: config}
  end

  test "pilot-only admission requires tracked stages and a valid cap", c do
    assert Assistant.readiness() == []
    refute Keyword.has_key?(c.config, :assistant_allocation)
    Application.put_env(:pauseai_ca, :agent_assistant, Keyword.delete(c.config, :stage_tracking))
    assert :stage_tracking in Assistant.readiness()
    assert {:error, :not_ready} = Assistant.set_enabled(c.scope, true)

    Application.put_env(:pauseai_ca, :agent_assistant, Keyword.put(c.config, :pilot_budget, %{}))
    assert :pilot_budget in Assistant.readiness()
    assert {:error, :not_ready} = Assistant.set_enabled(c.scope, true)
    refute_receive {:assistant_generated, _, _}
  end

  test "pilot-only reservations honor the shared cap and expose all-provider headroom", c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    assert {:ok, usage} = Assistant.token_usage(c.scope)
    assert usage.pilot.remaining_micros == 2000
    assert usage.pilot.limit_micros == 2000

    assert Map.keys(usage.pilot) |> Enum.sort() ==
             Enum.sort([
               :active,
               :accounted_micros,
               :remaining_micros,
               :limit_micros,
               :starts_at,
               :expires_at
             ])

    assert {:ok, _} = Assistant.reserve(c.scope, reservation(c.config), Assistant.configuration())
    assert {:ok, usage} = Assistant.token_usage(c.scope)
    assert usage.pilot.accounted_micros == 1000
    assert usage.pilot.remaining_micros == 1000
    assert usage.mode_availability["fast"].allowed

    assert {:ok, _} = Assistant.reserve(c.scope, reservation(c.config), Assistant.configuration())
    assert {:ok, usage} = Assistant.token_usage(c.scope)
    assert usage.pilot.remaining_micros == 0
    refute usage.mode_availability["fast"].allowed
    assert {:error, :forbidden} = Assistant.set_mode(c.scope, "fast")

    assert {:error, :mode_unavailable} =
             Assistant.reserve(c.scope, reservation(c.config), Assistant.configuration())

    assert Repo.aggregate(Store.Request, :count) == 2
    refute_receive {:assistant_generated, _, _}
  end

  test "pilot thresholds apply to mode changes without an allocation", c do
    pilot = %{c.config[:pilot_budget] | limit_micros: 4000}

    Application.put_env(
      :pauseai_ca,
      :agent_assistant,
      Keyword.put(c.config, :pilot_budget, pilot)
    )

    assert {:ok, _} = Assistant.set_enabled(c.scope, true)

    for _ <- 1..3 do
      assert {:ok, _} =
               Assistant.reserve(c.scope, reservation(c.config), Assistant.configuration())
    end

    assert {:ok, usage} = Assistant.token_usage(c.scope)
    assert usage.pilot.remaining_micros == 1000
    assert usage.mode_availability["fast"].allowed
    assert usage.mode_availability["normal"].allowed
    refute usage.mode_availability["high"].allowed
    assert {:error, :forbidden} = Assistant.set_mode(c.scope, "high")

    assert {:error, :mode_unavailable} =
             Assistant.reserve(
               c.scope,
               %{reservation(c.config) | mode: "high", model: "opus-fixture"},
               Assistant.configuration()
             )

    refute_receive {:assistant_generated, _, _}
  end

  test "settings and floating usage show the shared pilot cap in English and French", c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)

    for {locale, label} <- [{"en", "All-provider pilot"}, {"fr", "Essai tous fournisseurs"}] do
      {:ok, settings, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant?locale=#{locale}")
      assert has_element?(settings, "#assistant-pilot-budget", label)

      {:ok, floating, _} =
        live_isolated(log_in_user(c.conn, c.admin), PauseAiCaWeb.AssistantLive,
          session: %{
            "user_token" => Accounts.generate_user_session_token(c.admin),
            "site_locale" => locale
          }
        )

      assert has_element?(floating, "#site-assistant-usage", label)
    end

    refute_receive {:assistant_generated, _, _}
  end

  defp reservation(config) do
    %{
      request_id: Ecto.UUID.generate(),
      digest: String.duplicate("b", 64),
      mode: "fast",
      model: "haiku-fixture",
      max_output_tokens: config[:max_output_tokens],
      max_tokens: 4096,
      max_cost_micros: config[:max_turn_cost_micros]
    }
  end
end
