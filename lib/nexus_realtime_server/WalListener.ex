defmodule WalListener do
  use GenServer


  alias NexusRealtimeServer.Main

  def start_link(_opts) do
    config = Application.get_env(:nexus_realtime_server, WalListener)
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    host = String.to_charlist(config[:host])
    user = String.to_charlist(config[:user])
    password = String.to_charlist(config[:password])
    database = String.to_charlist(config[:database])

    opts = [
      database: database,
      port: config[:port],
      replication: "database"
    ]

    with {:ok, conn} <- :epgsql.connect(host, user, password, opts),
        :ok <- :epgsql.start_replication(conn, String.to_charlist(config[:slot]), self(), %{}, ~c"0/0", ~c"") do
      {:ok, %{conn: conn}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:epgsql, conn, {:x_log_data, _start_lsn, end_lsn, wal_record}}, state)
      when is_binary(wal_record) do
    print_latest_only(wal_record)
    :ok = :epgsql.standby_status_update(conn, end_lsn, end_lsn)
    {:noreply, state}
  end

  @impl true
  def handle_info({:epgsql, conn, {:x_log_data, _start_lsn, end_lsn, wal_record, _extra}}, state)
      when is_binary(wal_record) do
    print_latest_only(wal_record)
    :ok = :epgsql.standby_status_update(conn, end_lsn, end_lsn)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp print_latest_only(wal_record) do
    with {:ok, payload} <- Jason.decode(wal_record),
        changes when is_list(changes) <- payload["change"] do

      public_changes =
        Enum.filter(changes, fn
          %{"schema" => "public"} -> true
          _ -> false
        end)

      if public_changes != [] do
        #IO.puts("Received WAL changes:")
        Main.main(payload)
      end
    else
      _ -> :ok
    end
  end
end
