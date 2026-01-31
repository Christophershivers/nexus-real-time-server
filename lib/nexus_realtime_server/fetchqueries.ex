defmodule NexusRealtimeServer.FetchQueries do
  @moduledoc """
  Route-topic batching (per route_value topic).

  Client joins:   rt:<template_key>:<route_value>
  We broadcast:   rt:<template_key>:<route_value>

  Each work item contains:
    - template_sql: must SELECT route_key and include ANY($1)/ANY($2)
    - template_key: stable hash identifier for the SQL shape
    - route_values: MapSet of route values (usually ints/strings like "57")
    - ids: list of primary keys impacted by WAL payload (e.g. post ids)
    - event: phoenix event name to broadcast (e.g. "posts")
    - database_op: "insert" | "update" | "delete"
  """

  require Logger

  @max_concurrency String.to_integer(System.get_env("MAX_CONCURRENCY") || "10")
  @timeout String.to_integer(System.get_env("TIMEOUT") || "15000")



  def run(items) when is_list(items) do
    items
    |> Task.async_stream(&process_item/1,
      max_concurrency: @max_concurrency,
      timeout: @timeout,
      ordered: false
    )
    |> Stream.run()

    :ok
  end

  defp process_item(%{ids: ids}) when ids == [] or is_nil(ids), do: :ok

  defp process_item(item) do
    case to_string(item.database_op) do
      "delete" -> broadcast_deletes(item)
      _ -> execute_batched_and_broadcast(item)
    end
  end

  # ------------------------------------------------------------
  # Query once (route_values + ids), then split rows by route_key
  # and broadcast to rt:<template_key>:<route_value>
  # ------------------------------------------------------------
  defp execute_batched_and_broadcast(item) do
    route_values =
      item.route_values
      |> MapSet.to_list()

    ids_param =
      item.ids
      |> List.wrap()
      |> Enum.uniq()

    route_param = normalize_route_values(route_values)

    case NexusRealtimeServer.Repo.query(item.template_sql, [route_param, ids_param], timeout: @timeout) do
      {:ok, %Postgrex.Result{} = result} ->
        rows = rows_to_maps(result, item.database_op)

        # group rows by route_key
        rows_by_route =
          Enum.group_by(rows, fn row ->
            to_string(Map.get(row, "route_key"))
          end)

        Enum.each(route_values, fn rv ->
          topic = route_topic(item.template_key, rv)

          rows_for_route =
            rows_by_route
            |> Map.get(to_string(rv), [])
            |> Enum.map(&Map.delete(&1, "route_key"))

          if rows_for_route != [] do
            Logger.info(
              "broadcast topic=#{topic} event=#{item.event} rows=#{length(rows_for_route)}"
            )
             IO.puts("FetchQueries max_concurrency=#{@max_concurrency}")

            NexusRealtimeServerWeb.Endpoint.broadcast(topic, item.event, %{rows: rows_for_route, sent_at: System.system_time(:millisecond)})
          end
        end)

        :ok

      {:error, err} ->
        Logger.debug("[fetch] query error template_key=#{item.template_key} err=#{inspect(err)}")
        :ok
    end
  end

  defp broadcast_deletes(item) do
    route_values =
      item.route_values
      |> MapSet.to_list()

    rows =
      item.ids
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.map(fn id -> %{id: id, database_op: "delete"} end)

    Enum.each(route_values, fn rv ->
      topic = route_topic(item.template_key, rv)
      NexusRealtimeServerWeb.Endpoint.broadcast(topic, item.event, %{rows: rows, sent_at: System.system_time(:millisecond)})
    end)

    :ok
  end

  defp rows_to_maps(%Postgrex.Result{} = result, database_op) do
    Enum.map(result.rows, fn row ->
      result.columns
      |> Enum.zip(row)
      |> Map.new()
      |> Map.put("database_op", database_op)
    end)
  end

  # IMPORTANT: per-route topic
  defp route_topic(template_key, route_value) do
    "rt:" <> to_string(template_key) <> ":" <> to_string(route_value)
  end

  # Normalize route values for Postgrex encoding:
  # If every value is int-like => convert to integers for userid = ANY($1)
  defp normalize_route_values(values) when is_list(values) do
    if Enum.all?(values, &int_like?/1) do
      Enum.map(values, &to_int!/1)
    else
      Enum.map(values, &to_string/1)
    end
  end

  defp int_like?(v) when is_integer(v), do: true

  defp int_like?(v) when is_binary(v) do
    case Integer.parse(v) do
      {_i, ""} -> true
      _ -> false
    end
  end

  defp int_like?(_), do: false

  defp to_int!(v) when is_integer(v), do: v
  defp to_int!(v) when is_binary(v), do: String.to_integer(v)
end
