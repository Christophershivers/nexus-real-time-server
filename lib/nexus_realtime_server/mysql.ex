defmodule NexusRealtimeServer.MysqlRepo do
  use Ecto.Repo,
    otp_app: :nexus_realtime_server,
    adapter: Ecto.Adapters.MyXQL
end
