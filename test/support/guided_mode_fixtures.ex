defmodule PauseAiCa.GuidedModeFixtures do
  @moduledoc false
  defmodule Provider do
    defdelegate input_token_bound(request, mode, options),
      to: PauseAiCa.AssistantFixtures.Provider

    def generate(request, mode, options) do
      if options[:observer], do: send(options[:observer], {:guided_provider_called, request})
      manifest = Jason.decode!(request["context"]["guided_mode"]["manifest_json"])

      text =
        Keyword.get_lazy(options, :response_text, fn ->
          PauseAiCa.Assistant.GuidedMode.example_plan(manifest, "toronto_gta") |> Jason.encode!()
        end)

      {:ok,
       %{
         "text" => text,
         "model" => mode.model,
         "usage" => %{"input_tokens" => 70, "output_tokens" => 10}
       }}
    end
  end

  def configuration(observer) do
    PauseAiCa.AssistantFixtures.configuration(observer)
    |> Keyword.put(:provider, {Provider, [api_key: "synthetic-fixture", observer: observer]})
    |> Keyword.put(:features, [
      %{
        id: "crm-guided",
        title: "Guided geography",
        summary: "Read-only fixture",
        introduced_in: "0.6.14",
        entry_path: "/admin/contacts",
        enabled: true,
        ready: true,
        scenarios: ["CRM-ASSIST-GUIDE-01-en", "CRM-ASSIST-GUIDE-01-fr"]
      }
    ])
    |> Keyword.put(:feature_evidence, %{
      build: "guided-synthetic-fixture",
      results: %{"CRM-ASSIST-GUIDE-01-en" => "success", "CRM-ASSIST-GUIDE-01-fr" => "success"}
    })
  end

  def with_production_limits(config) do
    [guide | _] = config[:features]

    unrelated =
      for n <- 1..14 do
        %{
          id: "feature-#{n}",
          title: "Application feature #{n}",
          summary:
            "Reviewed application functionality and navigation available to the current administrator.",
          introduced_in: "0.7.0",
          entry_path: "/admin/contacts",
          enabled: true,
          ready: true,
          scenarios: guide.scenarios
        }
      end

    config
    |> Keyword.put(:max_turn_tokens, 16_384)
    |> Keyword.put(:max_output_tokens, 4096)
    |> Keyword.update!(:features, &(&1 ++ unrelated))
  end
end
