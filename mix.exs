defmodule PauseAiCa.MixProject do
  use Mix.Project

  def project do
    [
      app: :pauseai_ca,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {PauseAiCa.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, "test.atdd": :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:argon2_elixir, "~> 4.0"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      acceptance_harness_dependency(),
      {:phoenix_test_playwright, "~> 0.15.0", only: :test, runtime: false},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "test.atdd": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "assets.build",
        "cmd env ATDD=true mix test --only atdd --max-cases 1"
      ],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind pauseai_ca", "esbuild pauseai_ca"],
      "assets.deploy": [
        "compile",
        "tailwind pauseai_ca --minify",
        "esbuild pauseai_ca --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp acceptance_harness_dependency do
    case System.get_env("ACCEPTANCE_HARNESS_PATH") do
      path when is_binary(path) and path != "" ->
        {:acceptance_harness, path: Path.expand(path), override: true}

      _unset ->
        {:acceptance_harness, git: acceptance_harness_git_url(), tag: "v0.6.1"}
    end
  end

  defp acceptance_harness_git_url do
    case System.get_env("ACCEPTANCE_HARNESS_TOKEN") do
      credentials when is_binary(credentials) and credentials != "" ->
        {username, token} =
          case String.split(credentials, ":", parts: 2) do
            [username, token] -> {username, token}
            [token] -> {"oauth2", token}
          end

        "https://#{URI.encode_www_form(username)}:#{URI.encode_www_form(token)}@framagit.org/olivierg/acceptance_harness.git"

      _unset ->
        "git@framagit.org:olivierg/acceptance_harness.git"
    end
  end
end
