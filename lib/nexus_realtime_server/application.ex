defmodule NexusRealtimeServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
alias NexusRealtimeServer.ETSQueryCache

  use Application

  @impl true
  def start(_type, _args) do
    nexus_database = Application.get_env(:nexus_realtime_server, :nexus_database)

    IO.inspect(nexus_database, label: "Nexus Database")
    children = [
      NexusRealtimeServerWeb.Telemetry,
      case nexus_database do
        "postgresql" -> NexusRealtimeServer.Repo
        "mysql" -> NexusRealtimeServer.MysqlRepo
        _ -> nil
      end,
      {DNSCluster, query: Application.get_env(:nexus_realtime_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NexusRealtimeServer.PubSub},
      {Task.Supervisor, name: NexusRealtimeServer.BatchFlushSupervisor},
      # Start a worker by calling: NexusRealtimeServer.Worker.start_link(arg)
      # {NexusRealtimeServer.Worker, arg},
      # Start to serve requests, typically the last entry
      NexusRealtimeServerWeb.Endpoint,
      ETSQueryCache,
      NexusRealtimeServer.QueryBatcher,
      NexusRealtimeServer.DebeziumCollector
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
