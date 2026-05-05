defmodule VaporDemo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      VaporDemoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:vapor_demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: VaporDemo.PubSub},
      # Start a worker by calling: VaporDemo.Worker.start_link(arg)
      # {VaporDemo.Worker, arg},
      # Start to serve requests, typically the last entry
      VaporDemoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VaporDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VaporDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
