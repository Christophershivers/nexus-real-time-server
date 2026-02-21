defmodule NexusRealtimeServer.StripQuery do
  def strip_trailing_limit(sql) when is_binary(sql) do
    Regex.replace(~r/\s*\blimit\s+\d+\b\s*;?\s*$/i, sql, "")
    |> String.trim()
  end

  def strip_trailing_offset(sql) when is_binary(sql) do
    Regex.replace(~r/\s*\boffset\s+\d+\b\s*;?\s*$/i, sql, "")
    |> String.trim()
  end

  def strip_realtime_caps(sql) do
    sql
    |> strip_trailing_offset()
    |> strip_trailing_limit()
  end

end
