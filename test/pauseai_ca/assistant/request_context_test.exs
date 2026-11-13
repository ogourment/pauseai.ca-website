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
end
