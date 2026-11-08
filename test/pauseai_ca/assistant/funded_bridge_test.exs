defmodule PauseAiCa.Assistant.FundedBridgeTest do
  use PauseAiCa.DataCase, async: false
  import Ecto.Query
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Assistant, AssistantFixtures, Repo}
  alias PhoenixAgentAssistant.{CreditAllocation, FundedBudget, Store}
  alias PhoenixAgentAssistant.Store.{Request, SpendEntry}

  # This confirms local call ordering only, never a real external anchor receipt.
  defmodule Operations do
    def status(_), do: %{alerts: true, audit_anchor: true}

    def confirm(entry, options) do
      Agent.update(options[:state], &Map.update!(&1, :anchors, fn ids -> ids ++ [entry.id] end))
      :ok
    end
  end

  setup do
    previous = Application.fetch_env(:pauseai_ca, :agent_assistant)
    previous_build = System.get_env("PAUSEAI_CA_RELEASE_ID")
    System.put_env("PAUSEAI_CA_RELEASE_ID", "assistant-synthetic-fixture")
    state = start_supervised!({Agent, fn -> %{anchors: [], calls: []} end})

    admin =
      user_fixture(%{email: "funded-bridge-admin@example.org"})
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()

    other =
      user_fixture(%{email: "funded-bridge-other@example.org"})
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()

    member = user_fixture(%{email: "funded-bridge-member@example.org"})
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    plug = {Req.Test, __MODULE__}

    config =
      AssistantFixtures.configuration()
      |> Keyword.put(:stage_tracking, :required)
      |> Keyword.put(:max_daily_token_limit, 1_000_000)
      |> Keyword.put(
        :provider,
        {PhoenixAgentAssistant.OpenAI, [api_key: "SYNTHETIC-GENERATION", plug: plug]}
      )
      |> Keyword.put(:safety,
        moderation:
          {PhoenixAgentAssistant.Safety.OpenAIModeration,
           [api_key: "SYNTHETIC-MODERATION", model: "moderation-fixture", plug: plug]},
        jev:
          {PhoenixAgentAssistant.Safety.Jev,
           [api_key: "SYNTHETIC-JEV", model: "jev-fixture", plug: plug]}
      )
      |> Keyword.put(:operations_adapter, {Operations, [state: state]})
      |> Keyword.put(:assistant_allocation, %{
        currency: "USD",
        limit_micros: 100_000,
        allocation_ref: "fixture-assistant-only",
        organization_ref: "fixture-organization",
        starts_at: DateTime.add(now, -3600),
        expires_at: DateTime.add(now, 3600)
      })

    Application.put_env(:pauseai_ca, :agent_assistant, config)

    assert {:ok, _} =
             Store.set_enabled(
               Assistant.store(),
               admin.id,
               true,
               Ecto.UUID.generate(),
               config[:audit_keys]
             )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pauseai_ca, :agent_assistant, value)
        :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
      end

      if previous_build,
        do: System.put_env("PAUSEAI_CA_RELEASE_ID", previous_build),
        else: System.delete_env("PAUSEAI_CA_RELEASE_ID")
    end)

    Req.Test.stub(__MODULE__, fn _ ->
      flunk("unfunded or unavailable mode must not issue model HTTP")
    end)

    %{
      admin: admin,
      other: other,
      member: member,
      scope: Accounts.Scope.for_user(admin),
      config: config,
      state: state
    }
  end

  defp attest(c, config \\ nil, store \\ nil) do
    config = config || c.config
    store = store || Assistant.store()
    assert {:ok, expected} = FundedBudget.expected(config)

    assert {:ok, result} =
             CreditAllocation.attest(
               store,
               "synthetic-approved-operator",
               Map.put(expected, "receipt_sha256", String.duplicate("c", 64)),
               Ecto.UUID.generate(),
               config[:audit_keys]
             )

    assert :ok = Assistant.anchor_entry(result.entry, config)
    result
  end

  defp zero(config),
    do:
      Keyword.put(config, :assistant_allocation, %{
        currency: "USD",
        limit_micros: 0,
        allocation_ref: nil,
        organization_ref: nil,
        starts_at: nil,
        expires_at: nil
      })

  defp install_http(c) do
    Req.Test.stub(__MODULE__, fn conn ->
      number = Agent.get(c.state, &length(&1.calls))

      purpose =
        Enum.at(~w(input_moderation input_jev generation output_moderation output_jev), number)

      assert is_binary(purpose)

      ticket =
        Repo.one!(
          from(r in Request,
            where: r.actor_id == ^c.admin.id,
            order_by: [desc: r.inserted_at],
            limit: 1
          )
        )

      assert Repo.aggregate(
               from(e in SpendEntry, where: e.request_id == ^ticket.id and e.revision == 1),
               :count
             ) == 5

      row =
        Repo.one!(
          from(e in SpendEntry,
            where: e.request_id == ^ticket.id and e.purpose == ^purpose,
            order_by: [desc: e.revision],
            limit: 1
          )
        )

      assert row.payload["observation"]["state"] == "started"
      assert row.audit_ref in Agent.get(c.state, & &1.anchors)
      Agent.update(c.state, &Map.update!(&1, :calls, fn calls -> calls ++ [purpose] end))
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      case {conn.host, conn.request_path} do
        {"api.openai.com", "/v1/moderations"} ->
          Req.Test.json(conn, %{
            "model" => "moderation-fixture",
            "results" => [
              %{
                "flagged" => false,
                "categories" => %{"violence" => false},
                "category_scores" => %{"violence" => 0.0}
              }
            ]
          })

        {"api.typesafe.ai", "/v1/systemone"} ->
          Req.Test.json(conn, %{
            "model" => "jev-fixture",
            "answers" => %{
              "low" => %{"type" => "noul", "noul" => 1.0},
              "block" => %{"type" => "noul", "noul" => 0.0}
            },
            "usage" => %{"input_tokens" => 2}
          })

        {"api.openai.com", "/v1/responses"} ->
          Req.Test.json(conn, %{
            "object" => "response",
            "model" => payload["model"],
            "status" => "completed",
            "output" => [
              %{
                "type" => "message",
                "role" => "assistant",
                "status" => "completed",
                "content" => [
                  %{
                    "type" => "output_text",
                    "text" => "Synthetic released reply",
                    "annotations" => []
                  }
                ]
              }
            ],
            "usage" => %{"input_tokens" => 10, "output_tokens" => 7, "total_tokens" => 17}
          })

        _ ->
          flunk("unexpected model endpoint")
      end
    end)
  end

  defp request_count, do: Repo.aggregate(Request, :count)

  defp hold(c, actor, amount) do
    assert {:ok, row} =
             Store.reserve(
               Assistant.store(),
               actor,
               %{
                 request_id: Ecto.UUID.generate(),
                 digest: String.duplicate("d", 64),
                 mode: "fast",
                 model: "haiku-fixture",
                 max_output_tokens: c.config[:max_output_tokens]
               },
               c.config[:audit_keys],
               max_cost_micros: amount,
               daily_limit_micros: 1_000_000,
               max_tokens: 2048,
               daily_token_limit: 100_000,
               max_daily_token_limit: 1_000_000
             )

    row
  end

  test "explicit zero and positive-but-unattested funds prevent reservation and model HTTP", c do
    assert {:ok, ref} = Assistant.conversation(c.scope)
    before = request_count()

    for config <- [zero(c.config), c.config] do
      Application.put_env(:pauseai_ca, :agent_assistant, config)
      refute Assistant.visible?(c.scope)

      assert {:error, :unavailable} =
               Assistant.run(c.scope, Ecto.UUID.generate(), "Safe fixture question", ref)

      assert request_count() == before
    end

    assert Agent.get(c.state, & &1.calls) == []
  end

  test "attested positive allocation uses main bridge, five planned/anchored stages before actual adapter fixtures",
       c do
    attest(c)
    assert Assistant.readiness() == []
    assert {:ok, ref} = Assistant.conversation(c.scope)
    install_http(c)

    assert {:ok, %{text: "Synthetic released reply"}} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "Safe fixture question", ref)

    assert Agent.get(c.state, & &1.calls) ==
             ~w(input_moderation input_jev generation output_moderation output_jev)

    assert Repo.aggregate(from(e in SpendEntry, where: e.actor_id == ^c.admin.id), :count) == 15
    assert {:ok, usage} = Assistant.token_usage(c.scope)
    assert usage.reported_input == 10 and usage.reported_output == 7
    assert usage.pending_cost_micros == 0
  end

  test "High at75percent and Normal at90percent block forced submits without rewriting saved preferences",
       c do
    config =
      Keyword.put(c.config, :assistant_allocation, %{
        c.config[:assistant_allocation]
        | limit_micros: 10_000
      })

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    attest(c, config)
    assert {:ok, ref} = Assistant.conversation(c.scope)
    assert {:ok, _} = Assistant.set_mode(c.scope, "high")
    hold(c, c.other.id, 7500)
    assert {:ok, usage} = Assistant.token_usage(c.scope)
    assert usage.mode_availability["high"].allowed == false
    assert usage.mode_availability["normal"].allowed == true
    before = request_count()

    assert {:error, :unavailable} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "Forced High fixture", ref)

    assert request_count() == before and Assistant.mode(c.scope) == {:ok, "high"}
    assert {:ok, _} = Assistant.set_mode(c.scope, "normal")
    hold(c, c.other.id, 1500)
    assert {:ok, usage} = Assistant.token_usage(c.scope)
    assert usage.mode_availability["normal"].allowed == false
    assert usage.mode_availability["fast"].allowed == true
    before = request_count()

    assert {:error, :unavailable} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "Forced Normal fixture", ref)

    assert request_count() == before and Assistant.mode(c.scope) == {:ok, "normal"}
    assert Agent.get(c.state, & &1.calls) == []
  end

  test "admin money is actor-scoped while allocation authority is namespace and exact organization scoped",
       c do
    config = Keyword.put(c.config, :daily_limit_micros, 10_000)
    Application.put_env(:pauseai_ca, :agent_assistant, config)
    attest(c, config)
    hold(c, c.admin.id, 7500)
    assert {:ok, a} = Assistant.token_usage(c.scope)
    assert {:ok, b} = Assistant.token_usage(Accounts.Scope.for_user(c.other))
    refute a.mode_availability["high"].allowed
    assert b.mode_availability["high"].allowed

    mismatch =
      Keyword.put(config, :assistant_allocation, %{
        config[:assistant_allocation]
        | organization_ref: "other-organization"
      })

    Application.put_env(:pauseai_ca, :agent_assistant, mismatch)
    refute Assistant.visible?(c.scope)
    assert {:ok, ref} = Assistant.conversation(c.scope)
    before = request_count()

    assert {:error, :unavailable} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "Mismatched allocation fixture", ref)

    assert request_count() == before
  end

  test "foreign namespace attestation cannot enable this consumer", c do
    foreign = Store.new(Repo, "foreign-funding-fixture")

    assert {:ok, _} =
             Store.set_enabled(
               foreign,
               "operator",
               true,
               Ecto.UUID.generate(),
               c.config[:audit_keys]
             )

    attest(c, c.config, foreign)
    assert :credit_allocation in Assistant.readiness()
    assert {:ok, ref} = Assistant.conversation(c.scope)
    before = request_count()

    assert {:error, :unavailable} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "Foreign allocation fixture", ref)

    assert request_count() == before and Agent.get(c.state, & &1.calls) == []
  end

  test "retained own history survives funding loss but foreign and unprivileged access remains denied",
       c do
    attest(c)
    assert {:ok, ref} = Assistant.conversation(c.scope)
    install_http(c)

    assert {:ok, _} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "Retain this synthetic history", ref)

    Application.put_env(:pauseai_ca, :agent_assistant, zero(c.config))
    refute Assistant.visible?(c.scope)
    assert {:ok, history} = Assistant.history(c.scope, ref)
    assert Enum.any?(history, &(&1.text == "Synthetic released reply"))
    assert {:ok, ^ref} = Assistant.conversation(c.scope)
    assert {:ok, []} = Assistant.history(Accounts.Scope.for_user(c.other), ref)
    assert {:error, :forbidden} = Assistant.history(Accounts.Scope.for_user(c.member), ref)

    assert {:error, :unavailable} =
             Assistant.run(c.scope, Ecto.UUID.generate(), "No further effect", ref)

    assert length(Agent.get(c.state, & &1.calls)) == 5
  end

  test "a new active allocation or provider cannot authorize an older in-flight snapshot", c do
    attest(c)
    assert :ok = Assistant.authorize(c.scope, :safety, c.config)
    {:ok, expected} = FundedBudget.expected(c.config)

    assert {:ok, _} =
             CreditAllocation.revoke(
               Assistant.store(),
               "operator",
               expected["allocation_ref"],
               "retire-a",
               c.config[:audit_keys]
             )

    newer =
      Keyword.update!(
        c.config,
        :assistant_allocation,
        &%{&1 | allocation_ref: "replacement-allocation"}
      )

    attest(c, newer)
    Application.put_env(:pauseai_ca, :agent_assistant, newer)
    assert Assistant.visible?(c.scope)
    assert {:error, :forbidden} = Assistant.authorize(c.scope, :provider, c.config)
    assert :ok = Assistant.authorize(c.scope, :provider, newer)

    changed_provider =
      Keyword.update!(newer, :provider, fn {module, options} ->
        {module, Keyword.put(options, :api_key, "SYNTHETIC-ROTATED-KEY")}
      end)

    Application.put_env(:pauseai_ca, :agent_assistant, changed_provider)
    assert {:error, :forbidden} = Assistant.authorize(c.scope, :safety, newer)
    assert :ok = Assistant.authorize(c.scope, :safety, changed_provider)
    assert Agent.get(c.state, & &1.calls) == []
  end

  test "unchanged funded snapshots recheck revocation before another paid stage", c do
    attest(c)
    assert :ok = Assistant.authorize(c.scope, :safety, c.config)
    {:ok, expected} = FundedBudget.expected(c.config)

    {:ok, _} =
      CreditAllocation.revoke(
        Assistant.store(),
        "operator",
        expected["allocation_ref"],
        "revoke-before-generation",
        c.config[:audit_keys]
      )

    assert {:error, :forbidden} = Assistant.authorize(c.scope, :provider, c.config)
    assert Agent.get(c.state, & &1.calls) == []
  end

  test "captured execution cannot outlive a safety policy, reviewer, model, price, limit or audit binding change",
       c do
    initial = Keyword.put(c.config, :safety_policy, :text_coaching_v1)
    Application.put_env(:pauseai_ca, :agent_assistant, initial)
    attest(c, initial)
    admitted = Assistant.configuration()

    changes = [
      fn config -> Keyword.put(config, :safety_policy, :strict_v1) end,
      fn config ->
        Keyword.update!(config, :safety, fn safety ->
          Keyword.update!(safety, :jev, fn {module, options} ->
            {module, Keyword.put(options, :model, "new-jev-fixture-pin")}
          end)
        end)
      end,
      fn config ->
        Keyword.update!(config, :safety, fn safety ->
          Keyword.update!(safety, :moderation, fn {module, options} ->
            {module, Keyword.put(options, :api_key, "SYNTHETIC-NEW-REVIEW-KEY")}
          end)
        end)
      end,
      fn config ->
        Keyword.update!(config, :models, fn models ->
          %{models | "fast" => models["normal"], "normal" => models["fast"]}
        end)
      end,
      fn config ->
        Keyword.update!(config, :pricing, &Map.put(&1, "policy_id", "new-price-policy"))
      end,
      fn config -> Keyword.update!(config, :daily_limit_micros, &(&1 + 1000)) end,
      fn config -> Keyword.put(config, :allowed_modes, ~w(fast normal)) end,
      fn config ->
        Keyword.put(config, :anchor, endpoint: "https://example.invalid/changed-audit-binding")
      end,
      fn config ->
        Keyword.update!(
          config,
          :bindings,
          &put_in(&1, ["claude", "project_ref"], "new-project-binding")
        )
      end
    ]

    for change <- changes do
      updated = change.(initial)
      Application.put_env(:pauseai_ca, :agent_assistant, updated)
      assert Assistant.visible?(c.scope)

      for phase <- [:safety, :provider, :response] do
        assert {:error, :forbidden} = Assistant.authorize(c.scope, phase, admitted)
      end

      Application.put_env(:pauseai_ca, :agent_assistant, initial)
      assert :ok = Assistant.authorize(c.scope, :provider, admitted)
    end

    changed_audit_keys =
      Keyword.update!(admitted, :audit_keys, &%{&1 | id: "previous-audit-binding"})

    assert {:error, :forbidden} = Assistant.authorize(c.scope, :safety, changed_audit_keys)
    assert Agent.get(c.state, & &1.calls) == []
  end

  test "per-request preference, correlation, conversation and reservation closure do not change execution authority",
       c do
    attest(c)

    admitted =
      Assistant.configuration()
      |> Keyword.put(:preference, "normal")
      |> Keyword.put(:correlation_id, Ecto.UUID.generate())
      |> Keyword.put(:conversation_ref, Ecto.UUID.generate())
      |> Keyword.put(:spend_reservation_prepare, fn _ ->
        flunk("authorization must not invoke a callback")
      end)

    assert :ok = Assistant.authorize(c.scope, :safety, admitted)
    assert :ok = Assistant.authorize(c.scope, :provider, admitted)
    assert :ok = Assistant.authorize(c.scope, :response, admitted)
    assert Agent.get(c.state, & &1.calls) == []
  end
end
