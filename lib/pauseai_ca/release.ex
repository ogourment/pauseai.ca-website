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
        end)
    end
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
end
