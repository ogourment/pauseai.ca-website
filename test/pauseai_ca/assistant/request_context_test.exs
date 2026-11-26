defmodule PauseAiCa.Assistant.RequestContextTest do
  use ExUnit.Case, async: true
  alias PauseAiCa.Assistant.{FeatureCatalogue, RequestContext}
  alias PhoenixAgentAssistant.{Catalog, OpenAI, TextProviderHTTP}

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

  @tag :tmp_dir
  @tag :release_coaching
  test "published coaching summaries reach the serialized provider input whole", %{tmp_dir: dir} do
    version = Application.spec(:pauseai_ca, :vsn) |> to_string()

    identity = %{
      version: version,
      release_id: "pauseai-ca-#{version}-42",
      source_sha: String.duplicate("a", 40),
      pipeline_id: "42"
    }

    path = Path.join(dir, "catalogue.json")

    scenarios =
      for key <- ~w(HIST-EMAIL-01 TASK-MEMBER-01 TASK-PAI-01 TASK-PAI-01-authority),
          locale <- ~w(en fr),
          do: %{"id" => "#{key}-#{locale}", "status" => "success"}

    report = %{
      "schema_version" => "acceptance_harness.evidence.v1",
      "app" => %{"version" => version, "commit" => identity.source_sha, "pipeline_id" => "42"},
      "scenarios" => scenarios
    }

    {report, summaries} =
      case System.get_env("ASSISTANT_COACHING_PROJECTION") do
        nil ->
          {report,
           %{
             "HIST-EMAIL-01" => "Synthetic import coaching.",
             "TASK-MEMBER-01" => "Synthetic responsibility coaching.",
             "TASK-PAI-01" => "Synthetic task coaching."
           }}

        projection_path ->
          projection = projection_path |> File.read!() |> Jason.decode!()

          {Map.put(report, "scenarios", Map.fetch!(projection, "scenarios")),
           Map.fetch!(projection, "assistant_summaries")}
      end

    expected = %{
      "historical-email-import" => summaries["HIST-EMAIL-01"],
      "group-responsibilities" => summaries["TASK-MEMBER-01"],
      "organizer-tasks" => summaries["TASK-PAI-01"]
    }

    File.write!(path, Jason.encode!(Map.put(report, "assistant_summaries", summaries)))
    assert {:ok, loaded} = FeatureCatalogue.load(identity, evidence_path: path)
    features = provider_features(loaded, identity)

    File.write!(path, Jason.encode!(report))
    assert {:ok, incomplete} = FeatureCatalogue.load(identity, evidence_path: path)
    incomplete_features = provider_features(incomplete, identity)

    request = %{
      "text" =>
        "How can a Montréal group organizer record an ongoing Video Editor responsibility and assign the separate task of editing march footage to a member? Where can we check who owns the work and mark the task done?",
      "context" => %{
        "app_version" => version,
        "build" => "pauseai-ca-#{version}-45855868069",
        "locale" => "en",
        "features" => features,
        "history" => []
      },
      "attachments" => []
    }

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"input" => [%{"content" => content}]} = Jason.decode!(body)
      send(self(), {:model_request, Jason.decode!(content)})
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => %{}})
    end)

    # Match the published instruction byte counts and turn ceilings seen on 0.8.48.
    for {ceiling, instruction_bytes} <- [{16_384, 3582}, {32_768, 15_204}],
        {projected, coverage?} <- [{features, true}, {incomplete_features, false}] do
      request = put_in(request, ["context", "features"], projected)

      options = [
        instructions: String.duplicate("i", instruction_bytes),
        max_instruction_bytes: 24_000,
        api_key: "synthetic",
        plug: {Req.Test, __MODULE__}
      ]

      config =
        Keyword.merge(config(),
          max_turn_tokens: ceiling,
          provider: {OpenAI, options}
        )

      assert {:ok, bounded} = RequestContext.prepare(request, [], config, "normal")

      assert {:error, _} =
               OpenAI.generate(
                 bounded,
                 %{model: "synthetic-model", max_output_tokens: 4096},
                 options
               )

      assert_received {:model_request, %{"context" => %{"features" => sent_features}}}
      assert length(sent_features) == length(loaded.features)

      coaching = Enum.filter(sent_features, &Map.has_key?(expected, &1["id"]))
      assert length(coaching) == map_size(expected)

      assert %{"controls" => ["menu.contacts", "crm.geography.areas"]} =
               Enum.find(sent_features, &(&1["id"] == "crm-guided"))

      refute Enum.any?(sent_features, &(&1["controls"] == []))

      if coverage? do
        assert Enum.all?(coaching, &(&1["status"] == "available"))
        assert Map.new(coaching, &{&1["id"], &1["summary"]}) == expected
      else
        for feature <- coaching do
          assert feature["status"] == "disabled"
          assert feature["reason"] == "not_configured"
          assert feature["summary"] == feature["title"]
        end
      end

      assert bounded["text"] == request["text"]
      refute Enum.any?(sent_features, &Map.has_key?(&1, "scenarios"))

      {:ok, bound} = OpenAI.input_token_bound(bounded, %{}, options)

      assert bound + 4096 <= ceiling
      refute inspect(sent_features) =~ "HIST-EMAIL-01-en"
    end
  end

  defp provider_features(loaded, identity) do
    runtime = %{
      version: identity.version,
      build: identity.release_id,
      evidence: loaded.feature_evidence
    }

    loaded.features
    |> Catalog.for_actor(runtime, fn _ -> true end)
    |> RequestContext.catalogue()
    |> Jason.encode!()
    |> Jason.decode!()
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
