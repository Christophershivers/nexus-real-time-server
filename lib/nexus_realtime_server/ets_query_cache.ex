defmodule NexusRealtimeServer.ETSQueryCache do
  use GenServer

  @table :realtime_query
  @attrs [:sub_id, :topic, :user_id, :data]  # primary key MUST be first

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    :mnesia.stop()

    :mnesia.create_schema([node()])
    :mnesia.start()

    case :mnesia.create_table(@table, [
          attributes: @attrs,
          ram_copies: [node()],
          type: :set
        ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @table}} -> :ok
      other -> raise "create_table failed: #{inspect(other)}"
    end

    :mnesia.wait_for_tables([@table], 5000)

    :mnesia.add_table_index(@table, :topic)
    :mnesia.add_table_index(@table, :user_id)

    {:ok, %{}}
  end

end
