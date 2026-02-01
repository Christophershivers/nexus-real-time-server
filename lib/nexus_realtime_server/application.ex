defmodule NexusRealtimeServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
alias NexusRealtimeServer.ETSQueryCache

  use Application

  @impl true
  def start(_type, _args) do
    enable_postgres = Application.get_env(:nexus_realtime_server, :enable_postgres)
    children = [
      NexusRealtimeServerWeb.Telemetry,
      if(enable_postgres, do: NexusRealtimeServer.Repo, else: nil),
      {DNSCluster, query: Application.get_env(:nexus_realtime_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NexusRealtimeServer.PubSub},
      # Start a worker by calling: NexusRealtimeServer.Worker.start_link(arg)
      # {NexusRealtimeServer.Worker, arg},
      # Start to serve requests, typically the last entry
      NexusRealtimeServerWeb.Endpoint,
      WalListener,
      ETSQueryCache
    ]
    |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NexusRealtimeServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NexusRealtimeServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
