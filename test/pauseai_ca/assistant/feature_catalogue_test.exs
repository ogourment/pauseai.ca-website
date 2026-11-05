defmodule PauseAiCa.Assistant.FeatureCatalogueTest do
  use ExUnit.Case, async: false
  alias PauseAiCa.Assistant.FeatureCatalogue
  alias PhoenixAgentAssistant.Catalog

  setup do
    directory =
      Path.join(System.tmp_dir!(), "feature-evidence-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    version = Application.spec(:pauseai_ca, :vsn) |> to_string()

    identity = %{
      version: version,
      pipeline_id: "123456",
      release_id: "pauseai-ca-#{version}-123456",
      source_sha: String.duplicate("a", 40)
    }

    report = %{
      "schema_version" => "acceptance_harness.evidence.v1",
      "app" => %{
        "version" => identity.version,
        "pipeline_id" => identity.pipeline_id,
        "commit" => identity.source_sha
      },
      "run" => %{"id" => "native-run"},
      "scenarios" => [
        %{
          "id" => "GEO-PAI-01-en",
          "status" => "success",
          "steps" => [%{"private" => "never returned"}]
        },
        %{"id" => "GEO-PAI-01-fr", "status" => "ignored"}
      ]
    }

    %{path: Path.join(directory, "evidence.json"), identity: identity, report: report}
  end

  test "binds actual recorded outcomes and exposes no report bodies", context do
    write(context)
    assert {:ok, loaded} = FeatureCatalogue.load(context.identity, evidence_path: context.path)

    assert loaded.feature_evidence == %{
             build: context.identity.release_id,
             results: %{"GEO-PAI-01-en" => "success", "GEO-PAI-01-fr" => "ignored"}
           }

    refute inspect(loaded) =~ "never returned"
    feature = Enum.find(loaded.features, &(&1.id == "crm-geography"))

    runtime = %{
      version: context.identity.version,
      build: context.identity.release_id,
      evidence: loaded.feature_evidence
    }

    assert Catalog.describe(feature, runtime).status == :unverified

    assert Catalog.describe(feature, put_in(runtime.evidence.results["GEO-PAI-01-fr"], "success")).status ==
             :available

    assert Enum.all?(loaded.features, &Catalog.safe_path?(&1.entry_path))
  end

  test "GitHub evidence producer requires the CI pipeline mapping before release packaging",
       context do
    env_keys = ~w(GITHUB_RUN_ID CI_PIPELINE_ID PAUSEAI_CA_GIT_SHA GITHUB_SHA CI_COMMIT_SHA)
    previous_env = Map.new(env_keys, &{&1, System.get_env(&1)})
    previous_config = Application.fetch_env(:acceptance_harness, :harness)
    agent = Process.whereis(AcceptanceHarness.Evidence.Agent)
    previous_state = if agent, do: Agent.get(agent, & &1)
    directory = Path.dirname(context.path)

    on_exit(fn ->
      for {key, value} <- previous_env do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      case previous_config do
        {:ok, config} -> Application.put_env(:acceptance_harness, :harness, config)
        :error -> Application.delete_env(:acceptance_harness, :harness)
      end

      if agent do
        Agent.update(agent, fn _ -> previous_state end)
      else
        if current = Process.whereis(AcceptanceHarness.Evidence.Agent), do: Agent.stop(current)
      end
    end)

    Application.put_env(:acceptance_harness, :harness,
      otp_app: :pauseai_ca,
      app_name: "Synthetic release evidence",
      evidence_dir: directory,
      screenshot_dir: Path.join(directory, "screenshots"),
      commit_sha_env: ["PAUSEAI_CA_GIT_SHA", "GITHUB_SHA"]
    )

    System.put_env("GITHUB_RUN_ID", context.identity.pipeline_id)
    System.put_env("GITHUB_SHA", context.identity.source_sha)
    System.delete_env("PAUSEAI_CA_GIT_SHA")
    System.delete_env("CI_PIPELINE_ID")
    scenario = %{id: "GEO-PAI-01-en", title: "Synthetic producer contract", roles: []}

    produce = fn ->
      AcceptanceHarness.Evidence.reset!("Synthetic release evidence", [scenario])
      AcceptanceHarness.Evidence.mark_scenario_success!(scenario)
      AcceptanceHarness.Evidence.finalize!()
      context.path |> File.read!() |> Jason.decode!()
    end

    # Reproduce the actual staged schema: GitHub's native variable alone does
    # not populate the pinned producer's CI_PIPELINE_ID field.
    assert get_in(produce.(), ["app", "pipeline_id"]) == nil

    assert {:error, :unverified} =
             FeatureCatalogue.load(context.identity, evidence_path: context.path)

    System.put_env("CI_PIPELINE_ID", System.fetch_env!("GITHUB_RUN_ID"))
    assert get_in(produce.(), ["app", "pipeline_id"]) == context.identity.pipeline_id
    assert {:ok, loaded} = FeatureCatalogue.load(context.identity, evidence_path: context.path)
    assert loaded.feature_evidence.results == %{"GEO-PAI-01-en" => "success"}

    AcceptanceHarness.Evidence.record_step(
      "synthetic.png",
      "Large captured state",
      "Synthetic only",
      %{
        "scenario_id" => scenario.id,
        "scenario" => scenario.title,
        "captured_body" => String.duplicate("SYNTHETIC_PRIVATE_CAPTURE_BODY", 660_000)
      }
    )

    AcceptanceHarness.Evidence.finalize!()
    full_bytes = File.read!(context.path)
    assert byte_size(full_bytes) > 18 * 1024 * 1024

    assert {:error, :unverified} =
             FeatureCatalogue.load(context.identity, evidence_path: context.path)

    projection_path = context.path <> ".projection"

    assert :ok =
             FeatureCatalogue.package_projection(context.path, projection_path, context.identity)

    assert File.read!(context.path) == full_bytes
    projected_bytes = File.read!(projection_path)
    assert byte_size(projected_bytes) < 1024
    refute projected_bytes =~ "SYNTHETIC_PRIVATE_CAPTURE_BODY"
    refute projected_bytes =~ "screenshots"

    assert {:ok, projected} =
             FeatureCatalogue.load(context.identity, evidence_path: projection_path)

    assert projected == loaded

    for identity <- [
          %{context.identity | pipeline_id: "654321", release_id: "pauseai-ca-0.6.0-654321"},
          %{context.identity | source_sha: String.duplicate("b", 40)},
          %{context.identity | version: "0.6.1", release_id: "pauseai-ca-0.6.1-123456"}
        ] do
      assert {:error, :unverified} = FeatureCatalogue.load(identity, evidence_path: context.path)
    end
  end

  test "projection validates all identities and scenarios while emitting only bounded metadata",
       context do
    scenarios =
      for index <- 1..100,
          do: %{
            "id" => "SYNTHETIC-#{index}",
            "status" => if(rem(index, 2) == 0, do: "success", else: "ignored")
          }

    report = %{context.report | "scenarios" => scenarios}
    assert {:ok, projection} = FeatureCatalogue.project(report, context.identity)
    assert Map.keys(projection) |> Enum.sort() == ~w(app scenarios schema_version)
    assert projection["app"] == context.report["app"]

    assert Map.new(projection["scenarios"], &{&1["id"], &1["status"]}) ==
             Map.new(scenarios, &{&1["id"], &1["status"]})

    for invalid <- [
          put_in(report, ["app", "pipeline_id"], nil),
          put_in(report, ["app", "commit"], String.duplicate("b", 40)),
          put_in(report, ["app", "version"], context.identity.version <> "+mismatch"),
          %{report | "scenarios" => scenarios ++ [hd(scenarios)]},
          %{report | "scenarios" => [%{"id" => "bad", "status" => "invented"}]},
          %{
            report
            | "scenarios" => [%{"id" => String.duplicate("x", 161), "status" => "success"}]
          }
        ] do
      assert {:error, :unverified} = FeatureCatalogue.project(invalid, context.identity)
    end

    # The trusted build reader has its own finite cap; runtime remains2MiB.
    oversize = context.path <> ".oversize"
    {:ok, file} = :file.open(String.to_charlist(oversize), [:write, :binary])
    {:ok, _} = :file.position(file, 64 * 1024 * 1024)
    :ok = :file.write(file, "x")
    :ok = :file.close(file)
    destination = context.path <> ".projection"

    assert {:error, :unverified} =
             FeatureCatalogue.package_projection(oversize, destination, context.identity)

    refute File.exists?(destination)
  end

  test "rejects stale source, pipeline, version and release identities", context do
    write(context)

    for identity <- [
          Map.put(context.identity, :source_sha, String.duplicate("b", 40)),
          Map.put(context.identity, :pipeline_id, "654321"),
          Map.put(context.identity, :version, context.identity.version <> "+mismatch"),
          Map.put(context.identity, :release_id, "other-release"),
          Map.delete(context.identity, :source_sha)
        ] do
      assert {:error, :unverified} = FeatureCatalogue.load(identity, evidence_path: context.path)
    end
  end

  test "missing, malformed, nonregular and oversized evidence fails closed", context do
    assert {:error, :unverified} =
             FeatureCatalogue.load(context.identity, evidence_path: context.path)

    for bytes <- [
          "{",
          Jason.encode!(%{}),
          Jason.encode!(%{"padding" => String.duplicate("x", 2 * 1024 * 1024)})
        ] do
      File.write!(context.path, bytes)

      assert {:error, :unverified} =
               FeatureCatalogue.load(context.identity, evidence_path: context.path)
    end

    File.rm!(context.path)
    File.mkdir!(context.path)

    assert {:error, :unverified} =
             FeatureCatalogue.load(context.identity, evidence_path: context.path)
  end

  test "rejects duplicate IDs and unknown statuses rather than guessing", context do
    for scenarios <- [
          [%{"id" => "a", "status" => "passed"}],
          [%{"id" => "a", "status" => "success"}, %{"id" => "a", "status" => "failure"}],
          [%{"id" => "a"}],
          nil
        ] do
      write(%{context | report: Map.put(context.report, "scenarios", scenarios)})

      assert {:error, :unverified} =
               FeatureCatalogue.load(context.identity, evidence_path: context.path)
    end
  end

  test "all recognized non-success statuses retain their meaning", context do
    statuses = ~w(success failure running ignored not_run)
    scenarios = Enum.map(statuses, &%{"id" => &1, "status" => &1})
    write(%{context | report: Map.put(context.report, "scenarios", scenarios)})
    assert {:ok, loaded} = FeatureCatalogue.load(context.identity, evidence_path: context.path)
    assert loaded.feature_evidence.results == Map.new(statuses, &{&1, &1})
  end

  test "rollout flags disable tasks and groups despite passing evidence", context do
    flags = [:tasks_enabled, :incubators_enabled]
    previous = Map.new(flags, &{&1, Application.fetch_env(:pauseai_ca, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {flag, {:ok, value}} -> Application.put_env(:pauseai_ca, flag, value)
        {flag, :error} -> Application.delete_env(:pauseai_ca, flag)
      end)
    end)

    Enum.each(flags, &Application.put_env(:pauseai_ca, &1, false))
    write(context)
    assert {:ok, loaded} = FeatureCatalogue.load(context.identity, evidence_path: context.path)

    for id <- ["organizer-tasks", "group-admission"] do
      feature = Enum.find(loaded.features, &(&1.id == id))
      assert feature.enabled == false

      assert Catalog.describe(feature, %{
               version: context.identity.version,
               build: context.identity.release_id,
               evidence: loaded.feature_evidence
             }).status == :disabled
    end
  end

  test "symlinked reports are not accepted", context do
    write(context)
    link = context.path <> ".link"
    File.ln_s!(context.path, link)
    assert {:error, :unverified} = FeatureCatalogue.load(context.identity, evidence_path: link)
  end

  test "newsletter coaching starts at the workspace without advertising executable controls",
       context do
    write(context)
    assert {:ok, loaded} = FeatureCatalogue.load(context.identity, evidence_path: context.path)

    for id <- ["newsletter-compose", "newsletter-rich-paste"] do
      feature = Enum.find(loaded.features, &(&1.id == id))
      assert feature.entry_path == "/manage/mail"
      assert feature.controls == []
    end

    assert Enum.find(loaded.features, &(&1.id == "newsletter-compose")).scenarios == [
             "PA-NEWS-01-en",
             "PA-NEWS-01-fr",
             "MAIL-GEO-01-en",
             "MAIL-GEO-01-fr"
           ]
  end

  defp write(context), do: File.write!(context.path, Jason.encode!(context.report))
end
