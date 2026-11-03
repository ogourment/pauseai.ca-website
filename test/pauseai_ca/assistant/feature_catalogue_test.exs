defmodule PauseAiCa.Assistant.FeatureCatalogueTest do
  use ExUnit.Case, async: false
  alias PauseAiCa.Assistant.FeatureCatalogue
  alias PhoenixAgentAssistant.Catalog

  setup do
    directory =
      Path.join(System.tmp_dir!(), "feature-evidence-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    identity = %{
      version: "0.5.64",
      pipeline_id: "123456",
      release_id: "pauseai-ca-0.5.64-123456",
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

  test "rejects stale source, pipeline, version and release identities", context do
    write(context)

    for identity <- [
          Map.put(context.identity, :source_sha, String.duplicate("b", 40)),
          Map.put(context.identity, :pipeline_id, "654321"),
          Map.put(context.identity, :version, "0.5.65"),
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

  defp write(context), do: File.write!(context.path, Jason.encode!(context.report))
end
