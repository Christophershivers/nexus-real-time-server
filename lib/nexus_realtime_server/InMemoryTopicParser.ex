defmodule NexusRealtimeServer.InMemoryTopicParser do
  @moduledoc """
  Parses WAL payload changes, finds matching subscriptions (by topic + filter),
  and produces batched work items grouped by template_key.

  Option A output (single route topic per template_key):
    %{
      template_key: "...",
      template_sql: "...",   # must SELECT route_key and include ANY($1)/ANY($2)
      event: "posts",
      database_op: "insert" | "update" | "delete",
      route_values: MapSet.new(["57", "19", ...]),  # union of all subscribers' route_values
      ids: [1,2,3,...]
    }
  """

  require Logger

  def parse(payload) do
    parsed_changes = payloadParser(payload)
    all_topics = getAllTopics(parsed_changes)
    records_by_topic = getRecordsByTopic(all_topics)
    build_work_items(records_by_topic, parsed_changes)
  end

  # ------------------------------------------------------------
  # Build batched work items:
  # - loops changes, then records
  # - batches by {template_key, event, op}
  # - unions route_values across matching subscriptions
  # - accumulates pk ids affected
  # ------------------------------------------------------------
  defp build_work_items(records, parsed_changes) when is_list(parsed_changes) do
    acc =
      Enum.reduce(parsed_changes, %{}, fn change, acc0 ->
        Enum.reduce(records, acc0, fn {_topic, record}, acc1 ->
          pk    = record["pk"]
          event = record["event"]
          op    = to_string(change[:kind])

          template_sql = record["template_sql"]
          template_key = record["template_key"]

          # pk value from WAL payload (e.g., post id)
          pk_value = change[:columnValueName][pk]

          # subscription route set (supports scalar + list/MapSet)
          sub_route_set =
            case record["route_values"] || record["field_value"] do
              %MapSet{} = set ->
                set

              v when is_list(v) ->
                v |> Enum.map(&to_string/1) |> MapSet.new()

              nil ->
                MapSet.new()

              v ->
                MapSet.new([to_string(v)])
            end

          keep? =
            cond do
              is_nil(pk_value) ->
                false

              is_nil(template_sql) or is_nil(template_key) ->
                false

              MapSet.size(sub_route_set) == 0 ->
                false

              true ->
                field = record["table_field"]
                type  = change.columnNameTypes[field]
                eqop  = record["equality"]
                left_raw = change.columnValueName[field]

                # IMPORTANT:
                # For eq/!eq with a list subscription, we evaluate membership against sub_route_set.
                case type_family(type) do
                  :number  -> eval_value_or_set(:number,  eqop, left_raw, sub_route_set)
                  :boolean -> eval_value_or_set(:boolean, eqop, left_raw, sub_route_set)
                  :date    -> eval_value_or_set(:date,    eqop, left_raw, sub_route_set)
                  :uuid    -> eval_value_or_set(:uuid,    eqop, left_raw, sub_route_set)
                  :text    -> eval_value_or_set(:text,    eqop, left_raw, sub_route_set)
                end
            end

          if keep? do
            key = {template_key, event, op}

            Map.update(
              acc1,
              key,
              %{
                template_key: template_key,
                template_sql: template_sql,
                event: event,
                database_op: op,
                route_values: sub_route_set,
                ids: [pk_value],
                pk: pk,
                alias: record["alias"]
              },
              fn existing ->
                existing
                |> Map.put(:database_op, op) # last op wins for the batch key
                |> Map.update!(:route_values, fn set ->
                  MapSet.union(set, sub_route_set)
                end)
                |> Map.update!(:ids, fn ids -> [pk_value | ids] end)
              end
            )
          else
            acc1
          end
        end)
      end)

    acc
    |> Map.values()
    |> Enum.map(fn item ->
      %{item | ids: item.ids |> Enum.reverse() |> Enum.uniq()}
    end)
  end

  # ------------------------------------------------------------
  # Records by topic
  # ------------------------------------------------------------
  def getRecordsByTopic(allTopics) do
    allTopics
    |> Enum.uniq()
    |> Enum.flat_map(fn topic ->
      # index position 3 assumes record tuple:
      # {:realtime_query, sub_id, topic, user_id, record_map}
      case :mnesia.dirty_index_read(:realtime_query, topic, 3) do
        {:aborted, _} = err ->
          Logger.debug("[parser] dirty_index_read aborted: #{inspect(err)}")
          []

        rows when is_list(rows) ->
          Enum.map(rows, fn {:realtime_query, rec_id, topic2, _userid, record_map} ->
            {topic2, Map.put(record_map, "__rec_id", rec_id)}
          end)

        _ ->
          []
      end
    end)
  end

  # ------------------------------------------------------------
  # WAL payload parsing (delete normalization kept)
  # ------------------------------------------------------------
  def payloadParser(payload) do
    (payload["change"] || [])
    |> Enum.map(fn change0 ->
      change =
        if change0["kind"] == "delete" do
          columnNames  = change0["oldkeys"]["keynames"]
          columnTypes  = change0["oldkeys"]["keytypes"]
          columnValues = change0["oldkeys"]["keyvalues"]

          change0
          |> Map.drop(["oldkeys"])
          |> Map.put("columnnames", columnNames)
          |> Map.put("columntypes", columnTypes)
          |> Map.put("columnvalues", columnValues)
        else
          change0
        end

      columnNames  = change["columnnames"]
      columnTypes  = change["columntypes"]
      columnValues = change["columnvalues"]

      %{
        kind: change["kind"],
        table: change["table"],
        columnNames:  List.to_tuple(columnNames),
        columnTypes:  List.to_tuple(columnTypes),
        columnValues: List.to_tuple(columnValues),
        columnNameTypes: Enum.zip(columnNames, columnTypes) |> Map.new(),
        columnValueName: Enum.zip(columnNames, columnValues) |> Map.new()
      }
    end)
  end

  # topics like: "posts:userid", "posts:content", ...
  def getAllTopics(parsed_changes) when is_list(parsed_changes) do
    parsed_changes
    |> Enum.flat_map(fn %{table: table, columnNameTypes: name_types} ->
      Map.keys(name_types)
      |> Enum.map(fn field -> "#{table}:#{field}" end)
    end)
    |> Enum.uniq()
  end

  # ------------------------------------------------------------
  # Type helpers
  # ------------------------------------------------------------
  defp type_family(type) do
    case type do
      "smallint" -> :number
      "integer" -> :number
      "bigint" -> :number
      "real" -> :number
      "double precision" -> :number
      "numeric" -> :number
      "decimal" -> :number
      "double" -> :number
      "bigserial" -> :number

      "boolean" -> :boolean
      "date" -> :date
      "uuid" -> :uuid

      "text" -> :text
      "character varying" -> :text
      "varchar" -> :text

      _ -> :text
    end
  end

  defp compare_uuid("eq", left, right), do: left == right
  defp compare_uuid("!eq", left, right), do: left != right
  defp compare_uuid(_, _left, _right), do: false

  defp compare_text("eq", left, right), do: left == right
  defp compare_text("!eq", left, right), do: left != right
  defp compare_text("contains", left, right), do: String.contains?(left, right)
  defp compare_text("starts_with", left, right), do: String.starts_with?(left, right)
  defp compare_text("ends_with", left, right), do: String.ends_with?(left, right)
  defp compare_text(_, _left, _right), do: false

  defp cast(:number, v) when is_integer(v), do: {:ok, v}
  defp cast(:number, v) when is_float(v), do: {:ok, v}

  defp cast(:number, v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} -> {:ok, i}
      _ ->
        case Float.parse(v) do
          {f, ""} -> {:ok, f}
          _ -> :error
        end
    end
  end

  defp cast(:number, _), do: :error

  defp cast(:boolean, v) when is_boolean(v), do: {:ok, v}

  defp cast(:boolean, v) when is_binary(v) do
    case String.downcase(v) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> :error
    end
  end

  defp cast(:boolean, _), do: :error

  defp cast(:date, %Date{} = d), do: {:ok, d}
  defp cast(:date, v) when is_binary(v), do: Date.from_iso8601(v)
  defp cast(:date, _), do: :error

  defp cast(:uuid, v), do: {:ok, to_string(v)}
  defp cast(:text, v), do: {:ok, to_string(v)}

  defp compare("eq", l, r), do: l == r
  defp compare("!eq", l, r), do: l != r
  defp compare("gt", l, r), do: l > r
  defp compare("lt", l, r), do: l < r
  defp compare("gte", l, r), do: l >= r
  defp compare("lte", l, r), do: l <= r
  defp compare(_, _l, _r), do: false

  # MapSet variant (membership / not-membership)
  defp eval_value_or_set(family, op, left_raw, %MapSet{} = set) do
    with {:ok, left} <- cast(family, left_raw) do
      typed_set = cast_set(family, set)

      case op do
        "eq"  -> MapSet.member?(typed_set, left)
        "!eq" -> not MapSet.member?(typed_set, left)
        _     -> false
      end
    else
      _ -> false
    end
  end

  # scalar-to-scalar compare
  defp eval_value_or_set(family, op, left_raw, right_raw) do
    with {:ok, left} <- cast(family, left_raw),
         {:ok, right} <- cast(family, right_raw) do
      compare_by_family(family, op, left, right)
    else
      _ -> false
    end
  end

  defp cast_set(family, set) do
    Enum.reduce(set, MapSet.new(), fn v, acc ->
      case cast(family, v) do
        {:ok, typed} -> MapSet.put(acc, typed)
        _ -> acc
      end
    end)
  end

  defp compare_by_family(:uuid, op, left, right),
    do: compare_uuid(op, to_string(left), to_string(right))

  defp compare_by_family(:text, op, left, right),
    do: compare_text(op, to_string(left), to_string(right))

  defp compare_by_family(_family, op, left, right),
    do: compare(op, left, right)
end
