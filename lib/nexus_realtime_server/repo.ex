defmodule NexusRealtimeServer.Repo do
  use Ecto.Repo,
    otp_app: :nexus_realtime_server,
    adapter: Ecto.Adapters.Postgres
end
