defmodule MinecraftWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MinecraftWebWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:minecraft_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MinecraftWeb.PubSub},
      # Start a worker by calling: MinecraftWeb.Worker.start_link(arg)
      # {MinecraftWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      MinecraftWeb.RedisService,
      MinecraftWebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MinecraftWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MinecraftWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
