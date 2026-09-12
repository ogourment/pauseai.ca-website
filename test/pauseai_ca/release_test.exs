defmodule PauseAiCa.ReleaseTest do
  use PauseAiCa.DataCase, async: false

  test "records each deployment as an append-only version-history row" do
    path =
      Path.join(
        System.tmp_dir!(),
        "pauseai-deployments-#{System.unique_integer([:positive])}.jsonl"
      )

    names =
      ~w(PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH PAUSEAI_CA_CI_PIPELINE_ID CI_COMMIT_SHA PAUSEAI_CA_GIT_REF)

    previous = Map.new(names, &{&1, System.get_env(&1)})
    System.put_env("PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH", path)
    System.put_env("PAUSEAI_CA_CI_PIPELINE_ID", "31058041620")
    System.put_env("CI_COMMIT_SHA", "ff2f002")
    System.put_env("PAUSEAI_CA_GIT_REF", "main")

    on_exit(fn ->
      File.rm(path)

      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    first =
      PauseAiCa.Release.record_deployment(
        "pauseai-ca-0.2.2-31058041620",
        "staging",
        "blue",
        "0.2.2"
      )

    second =
      PauseAiCa.Release.record_deployment(
        "pauseai-ca-0.2.3-31060000000",
        "staging",
        "green",
        "0.2.3"
      )

    rows = path |> File.stream!() |> Enum.map(&Jason.decode!/1)
    assert Enum.map(rows, & &1["release_id"]) == [first.release_id, second.release_id]
    assert Enum.map(rows, & &1["app_version"]) == ["0.2.2", "0.2.3"]
    assert Enum.all?(rows, &(&1["environment"] == "staging"))
    assert Enum.all?(rows, &(&1["pipeline_id"] == "31058041620"))
  end

  test "packaged run and screenshot survive rotating release removal and retry" do
    root =
      Path.join(
        System.tmp_dir!(),
        "pauseai-release-evidence-#{System.unique_integer([:positive])}"
      )

    package = Path.join(root, "slot/priv/acceptance_evidence")
    File.mkdir_p!(Path.join(package, "screenshots"))
    File.write!(Path.join(package, "screenshots/step.png"), "immutable capture")

    evidence = %{
      "title" => "Release evidence",
      "run" => %{"id" => "release-test-run"},
      "scenarios" => []
    }

    File.write!(Path.join(package, "evidence.json"), Jason.encode!(evidence))
    old = System.get_env("PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH")
    System.put_env("PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH", Path.join(root, "shared/history.jsonl"))

    on_exit(fn ->
      if old,
        do: System.put_env("PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH", old),
        else: System.delete_env("PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH")

      File.rm_rf!(root)
    end)

    PauseAiCa.Release.import_acceptance_evidence(PauseAiCa.Repo, package)
    PauseAiCa.Release.import_acceptance_evidence(PauseAiCa.Repo, package)

    [[retained]] =
      Ecto.Adapters.SQL.query!(
        PauseAiCa.Repo,
        "SELECT source_dir FROM acceptance_harness_runs WHERE id = $1",
        ["release-test-run"]
      ).rows

    File.rm_rf!(Path.join(root, "slot"))
    assert File.read!(Path.join(retained, "screenshots/step.png")) == "immutable capture"
    assert File.regular?(Path.join(retained, "evidence.json"))

    [[1]] =
      Ecto.Adapters.SQL.query!(
        PauseAiCa.Repo,
        "SELECT count(*) FROM acceptance_harness_runs WHERE id = $1",
        ["release-test-run"]
      ).rows
  end
end
