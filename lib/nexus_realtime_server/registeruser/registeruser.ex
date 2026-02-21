defmodule NexusRealtimeServer.RegisterUser do
  alias NexusRealtimeServer.SQLGuard
  alias NexusRealtimeServer.BuildTemplate
  alias NexusRealtimeServer.StripQuery
  alias NexusRealtimeServer.NormalizeQuery
  alias NexusRealtimeServer.RegisterUser.Utils

  def register_user(payload) do
    # Validate incoming query
    SQLGuard.validate_selectish_single_statement!(payload["query"])
    # SQLGuard.validate_in_postgres_readonly!(NexusRealtimeServer.Repo, payload["query"])

    sub_id  = UUID.uuid4()
    key     = payload["topic"]   # e.g. "posts:userid" (used for mnesia lookup)
    user_id = payload["userid"]

    field_value_set =
      payload["field_value"]
      |> NormalizeQuery.normalize_route_values_set()

    table_field = payload["table_field"]
    pk          = payload["pk"]
    alias_      = payload["alias"]

    # keep original query for snapshot
    snapshot_query = payload["query"]

    # strip caps ONLY for what we store / use later for realtime refetch
    realtime_query =
      snapshot_query
      |> StripQuery.strip_realtime_caps()

    template_sql =
      realtime_query
      |> BuildTemplate.build_template_sql(table_field, pk, alias_)

    template_key =
      :crypto.hash(:sha256, template_sql) |> Base.encode16(case: :lower)

    # ✅ NEW: subscription hash (predicate group hash)
    # Include operator + value(s) so lte 57 != lte 100, etc.
    op = payload["operator"] || payload["equality"] || "eq"
    val_str = field_value_set |> MapSet.to_list() |> Enum.join(",")

    raw_sub_key = "#{template_key}:#{op}:#{val_str}"
    sub_hash = :crypto.hash(:sha256, raw_sub_key) |> Base.encode16(case: :lower)

    # ✅ NEW: topic is rt:<sub_hash> (no value suffix)
    route_topics = ["rt:" <> sub_hash]

    value =
      payload
      |> Map.drop(["topic"])
      |> Map.put("field_value", field_value_set)
      |> Map.put("template_sql", template_sql)
      |> Map.put("template_key", template_key)
      |> Map.put("sub_hash", sub_hash)
      |> Map.put("route_topics", route_topics)
      |> Map.put("query", realtime_query)          # overwrite query for realtime usage
      |> Map.put("snapshot_query", snapshot_query) # keep full one for snapshot/debug
      |> Map.put("equality", op)

    record = {:realtime_query, sub_id, key, user_id, value}
    :mnesia.transaction(fn -> :mnesia.write(record) end)

    # initial snapshot still uses the original query (limit stays)
    repo = Utils.active_repo() || raise "No repo configured (nexus_database is empty/unknown)"
    res  = Ecto.Adapters.SQL.query!(repo, snapshot_query, [])

    rows =
      Enum.map(res.rows, fn row ->
        res.columns
        |> Enum.zip(row)
        |> Map.new()
        |> Map.put("database_op", "query")
      end)

    %{route_topics: route_topics, rows: rows}
  end
end
