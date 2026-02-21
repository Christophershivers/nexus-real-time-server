defmodule NexusRealtimeServer.RegisterUser.Utils do
  def nexus_database do
    Application.get_env(:nexus_realtime_server, :nexus_database)
  end
  def find_where_paren_close(sql) do
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

  def scan_parens(sql, open_idx) do
    chars = String.to_charlist(sql)
    do_scan_parens(chars, open_idx, 0, 0)
  end

  def do_scan_parens(chars, open_idx, i, depth) do
    cond do
      i >= length(chars) -> :error
      i < open_idx -> do_scan_parens(chars, open_idx, i + 1, depth)

      true ->
        c = Enum.at(chars, i)

        cond do
          c == ?( ->
            do_scan_parens(chars, open_idx, i + 1, depth + 1)

          c == ?) ->
            new_depth = depth - 1
            if new_depth == 0, do: {:ok, i}, else: do_scan_parens(chars, open_idx, i + 1, new_depth)

          true ->
            do_scan_parens(chars, open_idx, i + 1, depth)
        end
    end
  end

  def active_repo do
    case Application.get_env(:nexus_realtime_server, :nexus_database, "") do
      "mysql" -> NexusRealtimeServer.MysqlRepo
      "postgresql" -> NexusRealtimeServer.Repo
      "postgres" -> NexusRealtimeServer.Repo
      _ -> nil
    end
  end
end
