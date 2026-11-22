defmodule PauseAiCa.Assistant.RequestContextTest do
  use ExUnit.Case, async: true
  alias PauseAiCa.Assistant.RequestContext
  alias PhoenixAgentAssistant.TextProviderHTTP

  defp config do
    [
      max_turn_tokens: 16_384,
      max_output_tokens: 4096,
      models: %{"normal" => %{model: "synthetic-model"}},
      provider: {TextProviderHTTP, [instructions: String.duplicate("i", 3209)]}
    ]
  end

  test "ordinary coaching retains every capability and guided planning selects registered capabilities" do
    features =
      for id <- ~w(contacts crm-guided crm-vancouver-guided),
          do: %{
            id: id,
            title: id,
            status: :available,
            entry_path: "/admin/contacts",
            build: "internal-build",
            app_version: "0.8.0",
            scenarios: ["INTERNAL-SCENARIO"]
          }

    coaching = RequestContext.catalogue(features)

    assert Enum.map(coaching, &Map.take(&1, [:id, :status, :entry_path])) ==
             Enum.map(features, &Map.take(&1, [:id, :status, :entry_path]))

    assert Enum.map(RequestContext.catalogue(features, ["crm-guided"]), & &1.id) == ["crm-guided"]
    refute inspect(coaching) =~ "INTERNAL-SCENARIO"
    refute inspect(coaching) =~ "internal-build"
  end

  test "history fits the provider bound and output allowance without altering the current question" do
    question = "How do I change a contact’s language?"
    request = %{"text" => question, "attachments" => [], "context" => %{"history" => []}}

    messages =
      for n <- 1..20,
          do: %{"role" => "assistant", "text" => "#{n}:" <> String.duplicate("x", 1490)}

    assert {:ok, result} = RequestContext.prepare(request, messages, config(), "normal")
    assert result["text"] == question
    assert result["context"]["history_truncated"]
    assert length(result["context"]["history"]) in 1..9
    assert List.last(result["context"]["history"]) == List.last(messages)

    assert {:ok, bound} =
             TextProviderHTTP.input_token_bound(result, %{},
               instructions: String.duplicate("i", 3209)
             )

    assert bound + 4096 <= 16_384
  end

  test "an oversized current message is rejected intact rather than silently shortened" do
    request = %{"text" => String.duplicate("x", 15_000), "context" => %{"history" => []}}
    assert {:error, :request_too_large} = RequestContext.prepare(request, [], config(), "normal")

    assert {:error, :token_limit_unavailable} =
             RequestContext.prepare(
               request,
               [],
               Keyword.put(config(), :max_turn_tokens, nil),
               "normal"
             )
  end

  test "published instruction length and the full catalogue fit all staging modes at 32,768" do
    instructions = String.duplicate("é", 9857)

    features =
      for id <- 1..15 do
        %{
          "id" => "fixture-feature-#{id}",
          "title" => "Synthetic organizer feature",
          "entry_path" => "/manage/example",
          "introduced_in" => "0.1.0",
          "summary" => String.duplicate("Guide the organizer to the next permitted step. ", 2),
          "status" => "available",
          "reason" => "verified_available"
        }
      end

    request = %{
      "text" => "Where can I find a local group? Give me the menu path in one sentence.",
      "context" => %{
        "locale" => "en",
        "app_version" => "0.8.36",
        "build" => "pauseai-ca-0.8.36-00000000",
        "history" => [],
        "features" => features
      },
      "attachments" => []
    }

    config =
      Keyword.merge(config(),
        max_turn_tokens: 32_768,
        models: Map.new(~w(fast normal high), &{&1, %{model: "synthetic-model"}}),
        provider: {TextProviderHTTP, [instructions: instructions, max_instruction_bytes: 24_000]}
      )

    for mode <- ~w(fast normal high) do
      assert {:ok, bounded} = RequestContext.prepare(request, [], config, mode)
      assert bounded["text"] == request["text"]
      assert bounded["context"]["features"] == features
      refute bounded["context"]["history_truncated"]

      assert {:error, :request_too_large} =
               RequestContext.prepare(
                 request,
                 [],
                 Keyword.put(config, :max_turn_tokens, 16_384),
                 mode
               )
    end

    oversized = Map.update!(request, "text", &(&1 <> String.duplicate("x", 12_000)))
    assert {:error, :request_too_large} = RequestContext.prepare(oversized, [], config, "normal")
  end
end
