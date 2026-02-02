import Config
import Dotenvy

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/nexus_realtime_server start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
env_dir_prefix = System.get_env("RELEASE_ROOT") || Path.expand(".")
source!([
  Path.absname(".env", env_dir_prefix),
  Path.absname(".#{config_env()}.env", env_dir_prefix),
  System.get_env() # Crucial: allows actual system vars to override files
])

filter_tables = System.get_env("FILTER_TABLES", "")
config :nexus_realtime_server, :filter_tables, filter_tables

enable_postgres =
  System.get_env("ENABLE_POSTGRES", "false")
  |> String.downcase()
  |> Kernel.==("true")

config :nexus_realtime_server, :enable_postgres, enable_postgres


cors_origins =
  System.get_env("CORS_ORIGINS", "http://localhost:3000")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)

# WebSocket Check Origins
websocket_origins =
  System.get_env("WEBSOCKET_ORIGINS", "http://localhost:3000")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)

config :nexus_realtime_server, :cors_origins, cors_origins
config :nexus_realtime_server, :websocket_origins, websocket_origins

config :nexus_realtime_server, WalListener,
    host: env!("HOSTNAME", :string),
    user: env!("DBUSERNAME", :string),
    password: env!("PASSWORD", :string),
    database: env!("DATABASE", :string),
    port: env!("DBPORT", :integer),
    slot: env!("SLOT", :string)

config :nexus_realtime_server, NexusRealtimeServer.Repo,
  username: env!("DBUSERNAME", :string),
  password: env!("PASSWORD", :string),
  hostname: env!("HOSTNAME", :string),
  database: env!("DATABASE", :string),
  port: env!("DBPORT", :integer),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: env!("POOL_SIZE", :integer)



if System.get_env("PHX_SERVER") do
  config :nexus_realtime_server, NexusRealtimeServerWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :nexus_realtime_server, NexusRealtimeServer.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
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
        # TRANSPORT OPTIONS MUST BE INSIDE THOUSAND_ISLAND_OPTIONS
        transport_options: [
          backlog: 8192
        ]
      ]
    ],
    secret_key_base: secret_key_base,
    check_origin: [
      "http://localhost:3000",
      "http://127.0.0.1:3000",
      "http://localhost:4000"
    ]



  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :nexus_realtime_server, NexusRealtimeServerWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :nexus_realtime_server, NexusRealtimeServerWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :nexus_realtime_server, NexusRealtimeServer.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
