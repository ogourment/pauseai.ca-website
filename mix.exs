defmodule PauseAiCa.MixProject do
  use Mix.Project

  def project do
    [
      app: :pauseai_ca,
      version: "0.8.0",
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
      preferred_envs: [format: :test, precommit: :test, "ci.test": :test, "test.atdd": :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp mail_workflow_dependency do
    case System.get_env("PHOENIX_MAIL_WORKFLOW_PATH") do
      path when is_binary(path) and path != "" ->
        {:phoenix_mail_workflow, path: Path.expand(path)}

      _ ->
        {:phoenix_mail_workflow,
         git: "https://github.com/ogourment/phoenix_mail_workflow-compiled.git",
         ref: "6b02ff9545ce42e3fb154f252915894549d6ee3f"}
    end
  end

  defp app_shell_dependency do
    case System.get_env("PHOENIX_APP_SHELL_PATH") do
      path when is_binary(path) and path != "" ->
        {:phoenix_app_shell, path: Path.expand(path)}

      _ ->
        {:phoenix_app_shell,
         git: "https://github.com/ogourment/phoenix_app_shell-compiled.git",
         ref: "6e5208c5ea6193faec4c8cfd2c08c82aa089933a"}
    end
  end

  defp agent_assistant_dependency do
    case System.get_env("PHOENIX_AGENT_ASSISTANT_PATH") do
      path when is_binary(path) and path != "" ->
        {:phoenix_agent_assistant, path: Path.expand(path)}

      _ ->
        {:phoenix_agent_assistant,
         git: "https://github.com/ogourment/phoenix_agent_assistant-compiled.git",
         ref: "64cc9f7c8dc1f5b80f6147197bd20ab390d6f976"}
    end
  end

  defp data_grid_dependency do
    case System.get_env("PHOENIX_DATA_GRID_PATH") do
      path when is_binary(path) and path != "" ->
        {:phoenix_data_grid, path: Path.expand(path)}

      _ ->
        {:phoenix_data_grid,
         git: "https://github.com/ogourment/phoenix_data_grid-compiled.git",
         ref: "7879f0379b9a5174bbd6eaf64534793fd6078be7"}
    end
  end

  defp deps do
    [
      data_grid_dependency(),
      app_shell_dependency(),
      agent_assistant_dependency(),
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
      mail_workflow_dependency(),
      cms_dependency(),
      donations_dependency(),
      tasks_dependency(),
      community_dependency(),
      crm_dependency(),
      markdown_editor_dependency(),
      {:mdex, "~> 0.13.5"},
      {:phoenix_test_playwright, "~> 0.15.0", only: :test, runtime: false},
      # Match the Playwright 1.62 timeout metadata protocol used by the locked driver.
      {:playwright_ex, "~> 0.8.0", only: :test, runtime: false},
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
      {:bandit, "1.14.1"}
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
        "acceptance.schema_diagram",
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
      "ci.test": [
        "format --check-formatted",
        "gettext.extract --check-up-to-date",
        "i18n.check",
        "compile --warnings-as-errors",
        "test"
      ],
      precommit: [
        # Extraction recompiles modules. Complete it before database tasks start the app.
        "format --check-formatted",
        "gettext.extract --check-up-to-date",
        "i18n.check",
        "compile --warnings-as-errors",
        # Use a fresh dependency graph and leave the lockfile unchanged.
        "cmd mix deps.unlock --check-unused",
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "acceptance.schema_diagram",
        "test"
      ]
    ]
  end

  defp donations_dependency do
    case System.get_env("PHOENIX_DONATIONS_PATH") do
      path when is_binary(path) and path != "" ->
        {:phoenix_donations, path: Path.expand(path)}

      _ ->
        {:phoenix_donations,
         git: "https://github.com/ogourment/phoenix_donations-compiled.git",
         ref: "bb95e2791b94e00456661d4d5e56b8dc6a673928"}
    end
  end

  defp tasks_dependency do
    case System.get_env("PHOENIX_TASKS_PATH") do
      nil ->
        {:phoenix_tasks,
         git: "https://github.com/ogourment/phoenix_tasks-compiled.git",
         ref: "f4204b41ea2f84aa9c6f64d3b97c4b774b7027d7"}

      path ->
        {:phoenix_tasks, path: path}
    end
  end

  defp community_dependency do
    case System.get_env("PHOENIX_COMMUNITY_PATH") do
      path when is_binary(path) and path != "" ->
        {:phoenix_community, path: path}

      _ ->
        {:phoenix_community,
         git: "https://github.com/ogourment/phoenix_community-compiled.git",
         ref: "4bcc56dca718c8720414f0d89ef4bbf5d4b0c2be"}
    end
  end

  defp crm_dependency do
    case System.get_env("PHOENIX_CRM_PATH") do
      path when is_binary(path) and path != "" ->
        {:phoenix_crm, path: path}

      _ ->
        {:phoenix_crm,
         git: "https://github.com/ogourment/phoenix_crm-compiled.git",
         ref: "135cbbd3258d72019356c6562ffd3c56125e8229"}
    end
  end

  defp markdown_editor_dependency do
    case System.get_env("PHOENIX_MARKDOWN_EDITOR_PATH") do
      path when is_binary(path) and path != "" ->
        {:phoenix_markdown_editor, path: path}

      _ ->
        {:phoenix_markdown_editor,
         git: "https://github.com/ogourment/phoenix_markdown_editor-compiled.git",
         ref: "79b34277a851bddc415fc236a91f670470056f7b"}
    end
  end

  defp cms_dependency do
    case System.get_env("PHOENIX_CMS_PATH") do
      path when is_binary(path) and path != "" ->
        {:phoenix_cms, path: Path.expand(path), override: true}

      _ ->
        {:phoenix_cms,
         git: "https://github.com/ogourment/phoenix_cms-compiled.git",
         ref: "8d750caebdc0e0d99a380bd9feaea6ea676be3eb"}
    end
  end

  defp acceptance_harness_dependency do
    case System.get_env("ACCEPTANCE_HARNESS_PATH") do
      path when is_binary(path) and path != "" ->
        {:acceptance_harness, path: Path.expand(path), override: true}

      _unset ->
        {:acceptance_harness,
         git: "https://github.com/ogourment/acceptance_harness-compiled.git",
         ref: "71100b379dd501c2aa2f08613fbeca98782a54b2"}
    end
  end
end
