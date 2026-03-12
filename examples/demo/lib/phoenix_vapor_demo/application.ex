defmodule PhoenixVaporDemo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhoenixVaporDemoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:phoenix_vapor_demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PhoenixVaporDemo.PubSub},
      # Start a worker by calling: PhoenixVaporDemo.Worker.start_link(arg)
      # {PhoenixVaporDemo.Worker, arg},
      # Start to serve requests, typically the last entry
      PhoenixVaporDemoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PhoenixVaporDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PhoenixVaporDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
