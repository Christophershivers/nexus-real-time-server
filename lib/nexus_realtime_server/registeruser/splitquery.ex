defmodule NexusRealtimeServer.SplitQuery do
  def inject_filters_safely(sql, _qualified_route, qualified_pk, db) do
    pk_filter =
      case db do
        "mysql" -> "#{qualified_pk} IN (?)"
        _ -> "#{qualified_pk} = ANY($1)"
      end

    {base, tail} = split_before_order_limit(sql)

    base_no_where =
      case split_on_where(base) do
        {:has_where, prefix_without_where} -> prefix_without_where
        :no_where -> String.trim_trailing(base)
      end

    String.trim_trailing(base_no_where) <> " WHERE " <> pk_filter <> " " <> tail
    |> String.trim()
  end

  def split_on_where(sql) do
    down = String.downcase(sql)

    case :binary.match(down, " where ") do
      :nomatch ->
        :no_where

      {idx, _len} ->
        # keep everything BEFORE " where "
        {prefix, _rest} = String.split_at(sql, idx)
        {:has_where, prefix}
    end
  end

  def split_before_order_limit(sql) do
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
end
