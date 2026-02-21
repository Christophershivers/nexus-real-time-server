defmodule NexusRealtimeServer.FetchQueries do
  require Logger

  @max_concurrency String.to_integer(System.get_env("MAX_CONCURRENCY") || "10")
  @timeout String.to_integer(System.get_env("TIMEOUT") || "15000")

  # -------------------------
  # ENTRY
  # -------------------------
  def run(items) when is_list(items) do
    t0 = now_ms()

    items
    |> Task.async_stream(&process_item/1,
      max_concurrency: @max_concurrency,
      timeout: @timeout,
      ordered: false
    )
    |> Stream.run()

    Logger.info("fetch_run total_ms=#{now_ms() - t0} items=#{length(items)}")
    :ok
  end

  defp process_item(%{ids: ids}) when ids == [] or is_nil(ids), do: :ok

  defp process_item(item) do
    t0 = now_ms()

    result =
      case to_string(item.database_op) do
        "delete" -> broadcast_deletes(item)
        _ -> fetch_then_broadcast(item)
      end

    Logger.info(
      "process_item template=#{item.template_key} op=#{item.database_op} " <>
        "ids=#{length(List.wrap(item.ids))} subs=#{MapSet.size(item.sub_hashes)} " <>
        "total_ms=#{now_ms() - t0}"
    )

    result
  end

  # ------------------------------------------------------------
  # MAIN FETCH PATH
  # ------------------------------------------------------------
  defp fetch_then_broadcast(item) do
    t0 = now_ms()

    sub_hashes = MapSet.to_list(item.sub_hashes)
    ids_param = item.ids |> List.wrap() |> Enum.uniq()

    case execute_batched_query(item, ids_param) do
      {:ok, rows, query_ms, rows_ms} ->
        {bcast_loop_ms, bcast_count, total_rows} =
          broadcast_rows(item, sub_hashes, rows)

        Logger.info(
          "fetch_breakdown template=#{item.template_key} " <>
            "db=#{nexus_database()} query_ms=#{query_ms} rows_ms=#{rows_ms} " <>
            "bcast_loop_ms=#{bcast_loop_ms} broadcasts=#{bcast_count} rows=#{total_rows} " <>
            "total_ms=#{now_ms() - t0}"
        )

        :ok

      {:error, err, query_ms} ->
        Logger.debug(
          "[fetch] query error template_key=#{item.template_key} db=#{nexus_database()} " <>
            "query_ms=#{query_ms} err=#{inspect(err)}"
        )

        :ok
    end
  end

  # ------------------------------------------------------------
  # STEP 1: EXECUTE
  # ------------------------------------------------------------
  defp execute_batched_query(item, ids_param) do
    repo = repo_for_env()
    sql0 = resolve_sql_for_db(item)
    db = nexus_database()

    IO.inspect(item, label: "Executing query for item", charlists: :as_lists)
    IO.inspect(sql0, label: "sql statement")

    {query_ms, query_result} =
      timed_ms(fn ->
        case db do
          "mysql" ->
            ids = List.wrap(ids_param)

            if ids == [] do
              {:ok, %{columns: [], rows: []}}
            else
              {sql1, flat_params} = mysql_expand_one_in_placeholder!(sql0, ids)
              IO.inspect(flat_params, label: "mysql params", charlists: :as_lists)
              repo.query(sql1, flat_params, timeout: @timeout)
            end

          _ ->
            repo.query(sql0, [ids_param], timeout: @timeout)
        end
      end)

    case query_result do
      {:ok, result} ->
        {rows_ms, rows} = timed_ms(fn -> rows_to_maps(result, item.database_op) end)
        {:ok, rows, query_ms, rows_ms}

      {:error, err} ->
        {:error, err, query_ms}
    end
  end

  # ------------------------------------------------------------
  # STEP 2: BROADCAST
  # ------------------------------------------------------------
  defp broadcast_rows(item, sub_hashes, rows) do
    {bcast_loop_ms, bcast_count} =
      timed_ms(fn ->
        Enum.reduce(sub_hashes, 0, fn sub_hash, acc ->
          topic = "rt:" <> to_string(sub_hash)

          {bcast_ms, _} =
            timed_ms(fn ->
              NexusRealtimeServerWeb.Endpoint.broadcast(
                topic,
                item.event,
                %{rows: rows, sent_at: System.system_time(:millisecond)}
              )
            end)

          Logger.info("broadcast_call_ms=#{bcast_ms} topic=#{topic} rows=#{length(rows)}")
          acc + 1
        end)
      end)

    {bcast_loop_ms, bcast_count, length(rows)}
  end

  # ------------------------------------------------------------
  # DELETE PATH
  # ------------------------------------------------------------
  defp broadcast_deletes(item) do
    t0 = now_ms()

    sub_hashes = MapSet.to_list(item.sub_hashes)

    rows =
      item.ids
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.map(fn id -> %{id: id, database_op: "delete"} end)

    Enum.each(sub_hashes, fn sub_hash ->
      topic = "rt:" <> to_string(sub_hash)

      NexusRealtimeServerWeb.Endpoint.broadcast(
        topic,
        item.event,
        %{rows: rows, sent_at: System.system_time(:millisecond)}
      )
    end)

    Logger.info(
      "delete_broadcast template=#{item.template_key} subs=#{length(sub_hashes)} " <>
        "rows=#{length(rows)} total_ms=#{now_ms() - t0}"
    )

    :ok
  end

  # ------------------------------------------------------------
  # DB SELECTION
  # ------------------------------------------------------------
  defp nexus_database do
    Application.get_env(:nexus_realtime_server, :nexus_database)
  end

  defp repo_for_env do
    case nexus_database() do
      "mysql" -> NexusRealtimeServer.MysqlRepo
      "postgres" -> NexusRealtimeServer.Repo
      "postgresql" -> NexusRealtimeServer.Repo
      other ->
        Logger.warning("Unknown NEXUS_DATABASE=#{inspect(other)}; defaulting to postgresql")
        NexusRealtimeServer.Repo
    end
  end

  defp resolve_sql_for_db(%{template_sql: sql} = _item) when is_binary(sql), do: sql

  defp resolve_sql_for_db(%{template_sql: sql_map} = item) when is_map(sql_map) do
    key =
      case nexus_database() do
        "mysql" -> :mysql
        "postgres" -> :postgresql
        "postgresql" -> :postgresql
        _ -> :postgresql
      end

    Map.get(sql_map, key) ||
      raise ArgumentError,
            "Missing template_sql for #{inspect(key)} on template_key=#{inspect(item.template_key)}"
  end

  # ------------------------------------------------------------
  # HELPERS
  # ------------------------------------------------------------
  defp rows_to_maps(%{columns: columns, rows: rows}, database_op)
       when is_list(columns) and is_list(rows) do
    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
      |> Map.put("database_op", database_op)
      |> Map.delete("route_key") # no longer needed for routing
    end)
  end

  defp rows_to_maps(other, _database_op) do
    raise ArgumentError,
          "Unsupported DB result shape: expected %{columns: ..., rows: ...}, got: #{inspect(other)}"
  end

  defp timed_ms(fun) do
    t1 = now_ms()
    res = fun.()
    {now_ms() - t1, res}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  # --- MySQL IN expansion helpers ---
  defp mysql_expand_one_in_placeholder!(sql, values) do
    placeholders =
      values
      |> Enum.map(fn _ -> "?" end)
      |> Enum.join(",")

    new_sql =
      case String.split(sql, "IN (?)", parts: 2) do
        [left, right] -> left <> "IN (" <> placeholders <> ")" <> right
        _ -> raise "Expected SQL to contain `IN (?)`: #{sql}"
      end

    {new_sql, values}
  end
end
