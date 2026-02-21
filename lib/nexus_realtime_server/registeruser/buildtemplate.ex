defmodule NexusRealtimeServer.BuildTemplate do

  alias NexusRealtimeServer.RegisterUser.Utils
  alias NexusRealtimeServer.SplitQuery

  def build_template_sql(sql, table_field, pk, alias_) do
    db = Utils.nexus_database()

    sql = sql |> String.trim() |> String.trim_trailing(";")

    qualified_route = qualify(alias_, table_field)
    qualified_pk    = qualify(alias_, pk)

    sql
    |> ensure_route_key_selected(qualified_route)
    |> SplitQuery.inject_filters_safely(qualified_route, qualified_pk, db)
  end

  def qualify(alias_, field) do
    case alias_ do
      a when is_binary(a) and byte_size(a) > 0 -> "#{a}.#{field}"
      _ -> field
    end
  end

  def ensure_route_key_selected(sql, qualified_route) do
    down = String.downcase(sql)

    if String.contains?(down, " as route_key") or String.contains?(down, " route_key") do
      sql
    else
      Regex.replace(~r/^\s*select\s+/i, sql, "select #{qualified_route} as route_key, ")
    end
  end

end
