defmodule PauseAiCa.AssistantFixtures do
  @moduledoc false
  defmodule Provider do
    def input_token_bound(request, _, options),
      do:
        {:ok, byte_size(Jason.encode!(request)) + byte_size(options[:instructions] || "") + 2048}

    def generate(request, mode, options) do
      if options[:observer], do: send(options[:observer], {:assistant_generated, request, mode})

      {:ok,
       %{
         "text" => "Use the contact filters to choose a city.",
         "model" => mode.model,
         "usage" => %{"input_tokens" => 70, "output_tokens" => 10}
       }}
    end
  end

  defmodule Moderation do
    def review(_, _),
      do:
        {:ok, %{flagged: false, categories: %{"violence" => false}, model: "moderation-fixture"}}
  end

  defmodule Jev do
    def review(request, _) do
      blocked = request["text"] == "synthetic blocked request"

      {:ok,
       %{
         risk: if(blocked, do: :block, else: :low),
         model: "jev-fixture",
         probabilities:
           if(blocked, do: %{"low" => 0.0, "block" => 1.0}, else: %{"low" => 1.0, "block" => 0.0})
       }}
    end
  end

  defmodule Operations do
    def status(_), do: %{audit_anchor: true, alerts: true}
    def confirm(_, _), do: :ok
  end

  def configuration(observer \\ nil) do
    [
      operations_adapter: {Operations, []},
      pricing: %{
        "currency" => "USD",
        "policy_id" => "synthetic-fixture",
        "models" =>
          Map.new(
            ~w(haiku-fixture sonnet-fixture opus-fixture),
            &{&1, %{"input_micros" => 1, "output_micros" => 1}}
          ),
        "jev_input_micros" => 1
      },
      audit_keys: %{
        encryption: :crypto.strong_rand_bytes(32),
        signing: :crypto.strong_rand_bytes(32),
        id: "synthetic-local-v1"
      },
      bindings: %{
        "claude" => %{"project_ref" => "synthetic-account"},
        "openai" => %{"project_ref" => "synthetic-account"},
        "jev" => %{"project_ref" => "synthetic-account"}
      },
      provider: {Provider, [api_key: "synthetic-fixture", observer: observer]},
      safety: [
        moderation: {Moderation, [api_key: "synthetic-fixture"]},
        jev: {Jev, [api_key: "synthetic-fixture"]}
      ],
      models: %{
        "fast" => %{model: "haiku-fixture"},
        "normal" => %{model: "sonnet-fixture"},
        "high" => %{model: "opus-fixture"}
      },
      daily_limit_micros: 100_000,
      max_turn_cost_micros: 1000,
      daily_token_limit: 100_000,
      max_turn_tokens: 32_768,
      max_output_tokens: 1024,
      alert_delivery_verified: true,
      audit_anchor_verified: true,
      price_policy_verified: true,
      features: [
        %{
          id: "contacts",
          title: "Contacts",
          summary: "Filter contacts by recorded geography.",
          introduced_in: "0.5.64",
          entry_path: "/admin/contacts",
          enabled: true,
          ready: true,
          scenarios: ["SYNTHETIC-CONTACTS-UI"]
        }
      ],
      feature_evidence: %{
        build: "assistant-synthetic-fixture",
        results: %{"SYNTHETIC-CONTACTS-UI" => "success"}
      }
    ]
  end
end
