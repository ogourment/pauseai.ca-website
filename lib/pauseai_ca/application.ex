defmodule PauseAiCa.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PauseAiCaWeb.Telemetry,
      PauseAiCa.Repo,
      PauseAiCa.Campaigns.RateLimit,
      {DNSCluster, query: Application.get_env(:pauseai_ca, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PauseAiCa.PubSub},
      # Start a worker by calling: PauseAiCa.Worker.start_link(arg)
      # {PauseAiCa.Worker, arg},
      # Start to serve requests, typically the last entry
      PauseAiCaWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PauseAiCa.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PauseAiCaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
