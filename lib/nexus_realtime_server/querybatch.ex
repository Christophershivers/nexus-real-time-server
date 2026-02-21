defmodule NexusRealtimeServer.QueryBatcher do
  @moduledoc """
  Batches query work items for a short window (default 500ms) to amortize
  PubSub/socket fan-out costs.

  Call `enqueue/1` with the list returned by InMemoryTopicParser.parse/1.
  """

  use GenServer
  require Logger

  alias NexusRealtimeServer.FetchQueries

  @flush_ms String.to_integer(System.get_env("BATCH_FLUSH_MS") || "200")
  @max_items String.to_integer(System.get_env("BATCH_MAX_ITEMS") || "10000")

  # Public API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def enqueue(items) when is_list(items) do
    # cast = async, won't block caller
    GenServer.cast(__MODULE__, {:enqueue, items})
  end

  # GenServer callbacks
  @impl true
  def init(_init_arg) do
    # state:
    #   buffer: list of items
    #   timer_ref: reference | nil
    state = %{buffer: [], timer_ref: nil}
    {:ok, state}
  end

  @impl true
  def handle_cast({:enqueue, items}, state) do
    state =
      state
      |> maybe_start_timer()
      |> add_items(items)

    # safety valve: if buffer explodes, flush early
    if length(state.buffer) >= @max_items do
      {:noreply, flush_now(state, :max_items)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    {:noreply, flush_now(state, :timer)}
  end

  # --- internals ---

  defp maybe_start_timer(%{timer_ref: nil} = state) do
    ref = Process.send_after(self(), :flush, @flush_ms)
    %{state | timer_ref: ref}
  end

  defp maybe_start_timer(state), do: state

  defp add_items(state, items) do
    # prepend for speed; we'll reverse on flush
    %{state | buffer: items ++ state.buffer}
  end

  defp flush_now(%{buffer: []} = state, _reason) do
    # nothing to do; clear timer
    cancel_timer(state)
    |> Map.put(:timer_ref, nil)
  end

  defp flush_now(state, reason) do
    cancel_timer(state)

    items =
      state.buffer
      |> Enum.reverse()

    t0 = System.monotonic_time(:millisecond)

    merged = merge_items(items)

    # Run your existing FetchQueries concurrently as it already does internally.
    FetchQueries.run(merged)

    dt = System.monotonic_time(:millisecond) - t0

    Logger.info(
      "batch_flush reason=#{reason} in_items=#{length(items)} merged_items=#{length(merged)} " <>
        "flush_ms=#{dt} window_ms=#{@flush_ms}"
    )

    %{state | buffer: [], timer_ref: nil}
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: ref} = state) do
    _ = Process.cancel_timer(ref)
    state
  end

  # Merge work items that can share a single DB query + broadcast pass.
  # This is where batching pays off hard.
  #
  # We merge by:
  #   template_sql + template_key + event + database_op + route_values
  # and union the `ids`.
  #
  # NOTE: We keep `route_values` as a MapSet, so it matches your FetchQueries.
  defp merge_items(items) do
    items
    |> Enum.reduce(%{}, fn item, acc ->
      key = merge_key(item)

      Map.update(acc, key, normalize_item(item), fn existing ->
        %{
          existing
          | ids: merge_ids(existing.ids, item.ids)
        }
      end)
    end)
    |> Map.values()
  end

  defp merge_key(item) do
    {
      item.template_sql,
      item.template_key,
      item.event,
      to_string(item.database_op),
      item.route_values
    }
  end

  defp normalize_item(item) do
    # ensure ids is a list (may be nil)
    Map.update(item, :ids, [], &List.wrap/1)
  end

  defp merge_ids(a, b) do
    (List.wrap(a) ++ List.wrap(b))
    |> Enum.uniq()
  end
end
