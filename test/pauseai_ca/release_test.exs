defmodule PauseAiCa.ReleaseTest do
  use ExUnit.Case, async: false

  test "records each deployment as an append-only version-history row" do
    path =
      Path.join(
        System.tmp_dir!(),
        "pauseai-deployments-#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)

    System.put_env("PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH", path)
    System.put_env("PAUSEAI_CA_CI_PIPELINE_ID", "31058041620")
    System.put_env("CI_COMMIT_SHA", "ff2f002")
    System.put_env("PAUSEAI_CA_GIT_REF", "main")

    on_exit(fn ->
      for name <-
            ~w(PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH PAUSEAI_CA_CI_PIPELINE_ID CI_COMMIT_SHA PAUSEAI_CA_GIT_REF) do
        System.delete_env(name)
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
end
