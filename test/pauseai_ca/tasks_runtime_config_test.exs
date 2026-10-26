defmodule PauseAiCa.TasksRuntimeConfigTest do
  use ExUnit.Case, async: false

  @environment_keys ~w(PAUSEAI_TASKS_ENABLED PAUSEAI_CA_DISPLAY_ENV PHX_HOST PHX_SERVER
    PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH DATABASE_URL SECRET_KEY_BASE BREVO_API_KEY
    PAUSEAI_CRM_INTAKE_TOKEN_FILE PAUSEAI_INCUBATORS_ENABLED PAUSEAI_WELCOME_CALLS_ENABLED
    PAUSEAI_MANIFUND_DONATIONS_ENABLED)

  setup do
    previous = Map.new(@environment_keys, &{&1, System.get_env(&1)})
    Enum.each(@environment_keys, &System.delete_env/1)

    # Reading runtime configuration needs synthetic release settings but never
    # starts the application, connects to PostgreSQL or configures a provider.
    System.put_env(%{
      "PAUSEAI_CA_DEPLOYMENT_HISTORY_PATH" => "/tmp/tasks-runtime-config-history.jsonl",
      "DATABASE_URL" => "ecto://synthetic:synthetic@localhost/tasks_runtime_config",
      "SECRET_KEY_BASE" => String.duplicate("synthetic-runtime-config-", 4)
    })

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    :ok
  end

  test "staging and local defaults enable Tasks while production and unknown releases stay disabled" do
    System.put_env("PAUSEAI_CA_DISPLAY_ENV", "staging")
    assert enabled?(:prod)

    System.put_env("PAUSEAI_CA_DISPLAY_ENV", "production")
    refute enabled?(:prod)

    System.delete_env("PAUSEAI_CA_DISPLAY_ENV")

    for host <- ["pauseai.ca", "pauseia.ca"] do
      System.put_env("PHX_HOST", host)
      refute enabled?(:prod)
    end

    System.put_env("PHX_HOST", "unknown.example.org")
    refute enabled?(:prod)
    System.put_env("PAUSEAI_CA_DISPLAY_ENV", "unexpected")
    refute enabled?(:prod)

    assert enabled?(:dev)
    assert enabled?(:test)
  end

  test "explicit override enables or disables Tasks in the same release and invalid values fail closed" do
    System.put_env("PAUSEAI_CA_DISPLAY_ENV", "production")
    System.put_env("PAUSEAI_TASKS_ENABLED", "true")
    assert enabled?(:prod)

    System.put_env("PAUSEAI_CA_DISPLAY_ENV", "staging")
    System.put_env("PAUSEAI_TASKS_ENABLED", "false")
    refute enabled?(:prod)
    refute enabled?(:dev)
    refute enabled?(:test)

    for value <- ["TRUE", "1", "", "unexpected"] do
      System.put_env("PAUSEAI_TASKS_ENABLED", value)
      refute enabled?(:prod)
    end
  end

  test "new pipeline features require an explicit per-environment rollout" do
    features = [
      incubators_enabled: "PAUSEAI_INCUBATORS_ENABLED",
      welcome_calls_enabled: "PAUSEAI_WELCOME_CALLS_ENABLED",
      manifund_donations_enabled: "PAUSEAI_MANIFUND_DONATIONS_ENABLED"
    ]

    for deployment <- ["staging", "production"] do
      System.put_env("PAUSEAI_CA_DISPLAY_ENV", deployment)

      for {feature, variable} <- features do
        read = fn ->
          Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
          |> Keyword.fetch!(:pauseai_ca)
          |> Keyword.fetch!(feature)
        end

        refute read.()
        System.put_env(variable, "true")
        assert read.()
        System.put_env(variable, "false")
        refute read.()
        System.put_env(variable, "TRUE")
        refute read.()
        System.delete_env(variable)
      end
    end
  end

  defp enabled?(environment) do
    Config.Reader.read!("config/runtime.exs", env: environment, target: :host)
    |> Keyword.fetch!(:pauseai_ca)
    |> Keyword.fetch!(:tasks_enabled)
  end
end
