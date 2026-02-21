import Config
import Dotenvy

env_dir_prefix = System.get_env("RELEASE_ROOT") || Path.expand(".")
source!([
  Path.absname(".env", env_dir_prefix),
  Path.absname(".#{config_env()}.env", env_dir_prefix),
  System.get_env() # system vars override dotenv files
])

filter_tables = System.get_env("FILTER_TABLES", "")
config :nexus_realtime_server, :filter_tables, filter_tables

flush_interval = System.get_env("FLUSH_INTERVAL", "2000")
  |> String.to_integer()
config :nexus_realtime_server, :flush_interval, flush_interval


# -------------------------
# NEXUS_DATABASE selection
# -------------------------
nexus_database =
  System.get_env("NEXUS_DATABASE", "")
  |> String.trim()
  |> String.downcase()

config :nexus_realtime_server, :nexus_database, nexus_database

# If other parts of your app still reference this, keep it derived
#enable_postgres = nexus_database in ["postgresql", "postgres"]
#config :nexus_realtime_server, :enable_postgres, enable_postgres

nexus_database = System.get_env("NEXUS_DATABASE", "")
    |> String.trim()
    |> String.downcase()

config :nexus_realtime_server, :nexus_database, nexus_database

# -------------------------
# CORS / WS origins
# -------------------------
cors_origins =
  System.get_env("CORS_ORIGINS", "http://localhost:3000")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)

websocket_origins =
  System.get_env("WEBSOCKET_ORIGINS", "http://localhost:3000")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)

config :nexus_realtime_server, :cors_origins, cors_origins
config :nexus_realtime_server, :websocket_origins, websocket_origins

# -------------------------
# Repo runtime config (DB-specific)
# -------------------------
pool_size =
  (System.get_env("POOL_SIZE") || "10")
  |> String.to_integer()

case nexus_database do
  "postgresql" ->
    config :nexus_realtime_server, NexusRealtimeServer.Repo,
      username: env!("DBUSERNAME", :string),
      password: env!("PASSWORD", :string),
      hostname: env!("HOSTNAME", :string),
      database: env!("DATABASE", :string),
      port: env!("DBPORT", :integer),
      stacktrace: true,
      show_sensitive_data_on_connection_error: true,
      pool_size: pool_size

  "postgres" ->
    config :nexus_realtime_server, NexusRealtimeServer.Repo,
      username: env!("DBUSERNAME", :string),
      password: env!("PASSWORD", :string),
      hostname: env!("HOSTNAME", :string),
      database: env!("DATABASE", :string),
      port: env!("DBPORT", :integer),
      stacktrace: true,
      show_sensitive_data_on_connection_error: true,
      pool_size: pool_size

  "mysql" ->
    config :nexus_realtime_server, NexusRealtimeServer.MysqlRepo,
      username: env!("DBUSERNAME", :string),
      password: env!("PASSWORD", :string),
      hostname: env!("HOSTNAME", :string),
      database: env!("DATABASE", :string),
      port: env!("DBPORT", :integer),
      stacktrace: true,
      show_sensitive_data_on_connection_error: true,
      pool_size: pool_size

  "" ->
    # no DB configured
    :ok

  other ->
    IO.warn("Unknown NEXUS_DATABASE=#{inspect(other)}; no repo configured")
    :ok
end

# -------------------------
# Endpoint server enable
# -------------------------
if System.get_env("PHX_SERVER") do
  config :nexus_realtime_server, NexusRealtimeServerWeb.Endpoint, server: true
end

# -------------------------
# Production release config
# -------------------------
if config_env() == :prod do
  # Your current prod block configures DATABASE_URL for Postgres Repo.
  # Only do that when Postgres is selected, otherwise mysql/no-db releases break.
  if nexus_database in ["postgresql", "postgres"] do
    database_url =
      System.get_env("DATABASE_URL") ||
        raise """
        environment variable DATABASE_URL is missing.
        For example: ecto://USER:PASS@HOST/DATABASE
        """

    maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

    config :nexus_realtime_server, NexusRealtimeServer.Repo,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      socket_options: maybe_ipv6
  end

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :nexus_realtime_server, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :nexus_realtime_server, NexusRealtimeServerWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port,
      thousand_island_options: [
        num_acceptors: 25,
        num_connections: 20000,
        transport_options: [backlog: 8192]
      ]
    ],
    secret_key_base: secret_key_base,
    check_origin: [
      "http://localhost:3000",
      "http://127.0.0.1:3000",
      "http://localhost:4000"
    ]
end
