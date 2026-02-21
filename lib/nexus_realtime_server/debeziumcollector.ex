defmodule NexusRealtimeServer.DebeziumCollector do
  use GenServer
  alias NexusRealtimeServer.Main

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def add_event(event) do
    GenServer.cast(__MODULE__, {:add, event})
  end

  @impl true
  def init(_opts) do
    flush_interval =
      Application.get_env(:nexus_realtime_server, :flush_interval, 2000)

    {:ok, %{events: [], flush_interval: flush_interval, timer_ref: nil}}
  end

  @impl true
  def handle_cast({:add, event}, state) do
    state = %{state | events: [event | state.events]}
    IO.inspect(state.flush_interval, label: "flushing time:")
    # Start timer ONLY on first event when idle
    state =
      case state.timer_ref do
        nil ->
          ref = Process.send_after(self(), :flush, state.flush_interval)
          %{state | timer_ref: ref}

        _ref ->
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush, state) do
    # Flush once, then go idle again
    events = Enum.reverse(state.events)

    if events != [] do
      IO.inspect(length(events), label: "--- FLUSHING BATCH ---")
      Main.main(events)
    end

    {:noreply, %{state | events: [], timer_ref: nil}}
  end
end
