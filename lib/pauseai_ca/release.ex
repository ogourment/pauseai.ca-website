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
        end)
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
