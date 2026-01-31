defmodule NexusRealtimeServer.RegisterUser do
  @moduledoc false
  alias NexusRealtimeServer.SQLGuard

  def register_user(payload) do
    SQLGuard.validate_selectish_single_statement!(payload["query"])
    SQLGuard.validate_in_postgres_readonly!(NexusRealtimeServer.Repo, payload["query"])

    sub_id  = UUID.uuid4()
    key     = payload["topic"]        # e.g. "posts:userid"
    user_id = payload["userid"]

    # normalize field_value to MapSet of strings (stable, predictable)
    field_value_set =
      payload["field_value"]
      |> normalize_route_values_set()

    table_field = payload["table_field"]  # route field (e.g. "userid")
    pk          = payload["pk"]
    alias_      = payload["alias"]
    query       = payload["query"]

    template_sql =
      query
      |> build_template_sql(table_field, pk, alias_)

    template_key =
      :crypto.hash(:sha256, template_sql) |> Base.encode16(case: :lower)

    # ✅ IMPORTANT: one route topic per route value
    route_topics =
      field_value_set
      |> MapSet.to_list()
      |> Enum.map(fn rv -> route_topic(template_key, rv) end)

    value =
      payload
      |> Map.drop(["topic"])
      |> Map.put("field_value", field_value_set)
      |> Map.put("template_sql", template_sql)
      |> Map.put("template_key", template_key)
      |> Map.put("route_topics", route_topics)

    record = {:realtime_query, sub_id, key, user_id, value}
    :mnesia.transaction(fn -> :mnesia.write(record) end)

    # Snapshot query stays the same:
    res = Ecto.Adapters.SQL.query!(NexusRealtimeServer.Repo, query, [])

    rows =
      Enum.map(res.rows, fn row ->
        res.columns
        |> Enum.zip(row)
        |> Map.new()
        |> Map.put("database_op", "query")
      end)

    %{route_topics: route_topics, rows: rows}
  end

  # ------------------------------------------------------------
  # Route topics MUST MATCH FetchQueries.route_topic/2
  # ------------------------------------------------------------
  defp route_topic(template_key, route_value) do
    "rt:" <> to_string(template_key) <> ":" <> to_string(route_value)
  end

  # Normalize "field_value" into a MapSet of strings
  defp normalize_route_values_set(v) when is_list(v) do
    v
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp normalize_route_values_set(%MapSet{} = set) do
    set
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp normalize_route_values_set(nil), do: MapSet.new()

  defp normalize_route_values_set(v) do
    s = v |> to_string() |> String.trim()
    if s == "", do: MapSet.new(), else: MapSet.new([s])
  end

  # --- helpers for template_sql ---

  defp build_template_sql(sql, table_field, pk, alias_) do
    sql = sql |> String.trim() |> String.trim_trailing(";")

    qualified_route = qualify(alias_, table_field)
    qualified_pk    = qualify(alias_, pk)

    sql
    |> ensure_route_key_selected(qualified_route)
    |> inject_filters_safely(qualified_route, qualified_pk)
  end

  defp qualify(alias_, field) do
    case alias_ do
      a when is_binary(a) and byte_size(a) > 0 -> "#{a}.#{field}"
      _ -> field
    end
  end

  defp ensure_route_key_selected(sql, qualified_route) do
    down = String.downcase(sql)

    if String.contains?(down, " as route_key") or String.contains?(down, " route_key") do
      sql
    else
      Regex.replace(~r/^\s*select\s+/i, sql, "select #{qualified_route} as route_key, ")
    end
  end

  # Inject WHERE safely before ORDER BY / LIMIT if needed
  defp inject_filters_safely(sql, qualified_route, qualified_pk) do
    case find_where_paren_close(sql) do
      {:ok, close_idx} ->
        {head, tail} = String.split_at(sql, close_idx + 1)

        head <>
          " AND #{qualified_route} = ANY($1) AND #{qualified_pk} = ANY($2)" <>
          tail

      :error ->
        {base, tail} = split_before_order_limit(sql)

        base <>
          " WHERE #{qualified_route} = ANY($1) AND #{qualified_pk} = ANY($2) " <>
          tail
    end
  end

  defp split_before_order_limit(sql) do
    down = String.downcase(sql)

    order_idx =
      case :binary.match(down, " order by ") do
        :nomatch -> nil
        {idx, _} -> idx
      end

    limit_idx =
      case :binary.match(down, " limit ") do
        :nomatch -> nil
        {idx, _} -> idx
      end

    cut =
      [order_idx, limit_idx]
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> byte_size(sql) end)

    String.split_at(sql, cut)
  end

  defp find_where_paren_close(sql) do
    down = String.downcase(sql)

    case :binary.match(down, "where") do
      :nomatch ->
        :error

      {where_idx, _len} ->
        after_where = binary_part(down, where_idx, byte_size(down) - where_idx)

        case :binary.match(after_where, "(") do
          :nomatch -> :error
          {rel_open_idx, _} ->
            open_idx = where_idx + rel_open_idx
            scan_parens(sql, open_idx)
        end
    end
  end

  defp scan_parens(sql, open_idx) do
    chars = String.to_charlist(sql)
    do_scan_parens(chars, open_idx, 0, 0)
  end

  defp do_scan_parens(chars, open_idx, i, depth) do
    cond do
      i >= length(chars) -> :error
      i < open_idx -> do_scan_parens(chars, open_idx, i + 1, depth)
      true ->
        c = Enum.at(chars, i)

        cond do
          c == ?( -> do_scan_parens(chars, open_idx, i + 1, depth + 1)
          c == ?) ->
            new_depth = depth - 1
            if new_depth == 0, do: {:ok, i}, else: do_scan_parens(chars, open_idx, i + 1, new_depth)
          true -> do_scan_parens(chars, open_idx, i + 1, depth)
        end
    end
  end
end
