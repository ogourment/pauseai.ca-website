defmodule PauseAiCa.Release do
  @moduledoc """
  Release-time database operations used by the deployment harness.
  """

  @app :pauseai_ca

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
          AcceptanceHarness.AdminStore.install!(repo: repo)
          import_acceptance_evidence(repo)
        end)
    end
  end

  @doc "Imports evidence packaged with this exact release without starting HTTP or workers."
  def import_acceptance_evidence(repo, evidence_dir \\ nil) do
    dir = evidence_dir || Application.app_dir(@app, "priv/acceptance_evidence")
    path = Path.join(dir, "evidence.json")

    if File.regular?(path) do
      retained_dir = retain_acceptance_evidence(dir)
      retained_path = Path.join(retained_dir, "evidence.json")

      AcceptanceHarness.AdminStore.import_evidence!(retained_path,
        repo: repo,
        source_dir: retained_dir
      )

      IO.puts("Imported packaged acceptance evidence from #{path}")
    else
      IO.puts("No packaged acceptance evidence (local build).")
    end
  end

  defp retain_acceptance_evidence(dir) do
    case System.get_env("PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH") do
      nil ->
        dir

      history_path ->
        evidence = dir |> Path.join("evidence.json") |> File.read!() |> Jason.decode!()
        run_id = get_in(evidence, ["run", "id"])

        unless is_binary(run_id) and Regex.match?(~r/\A[a-zA-Z0-9._-]+\z/, run_id),
          do: raise("Invalid acceptance run identity")

        destination = Path.join([Path.dirname(history_path), "acceptance_evidence", run_id])
        manifest = Path.join(destination, "evidence.json")

        if File.exists?(manifest) and
             File.read!(manifest) != File.read!(Path.join(dir, "evidence.json")),
           do: raise("Acceptance run identity collision")

        File.mkdir_p!(destination)
        File.cp_r!(dir, destination)
        destination
    end
  end

  def record_deployment(release_id, target_env, color, version) do
    path = System.fetch_env!("PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH")

    entry = %{
      release_id: release_id,
      environment: target_env,
      slot: color,
      app_version: version,
      pipeline_id: System.get_env("PAUSEAI_CA_CI_PIPELINE_ID"),
      pipeline_url: System.get_env("CI_PIPELINE_URL"),
      git_sha: System.get_env("CI_COMMIT_SHA"),
      git_ref: System.get_env("PAUSEAI_CA_GIT_REF"),
      git_messages: decoded_env("CI_DEPLOY_COMMIT_MESSAGES_B64"),
      deployed_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, [Jason.encode!(entry), "\n"], [:append])
    entry
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seed_script = Application.app_dir(@app, "priv/repo/seeds.exs")
          Code.eval_file(seed_script)
        end)
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.load(@app)

  defp decoded_env(name) do
    with value when is_binary(value) and value != "" <- System.get_env(name),
         {:ok, decoded} <- Base.decode64(value) do
      decoded
    else
      _ -> nil
    end
  end
end
