defmodule NexusRealtimeServer.WorkItems do
  alias NexusRealtimeServer.Utils
  def buildWorkItems(records, parsed_changes) when is_list(parsed_changes) do
    acc =
      Enum.reduce(parsed_changes, %{}, fn change, acc0 ->
        Enum.reduce(records, acc0, fn {_topic, record}, acc1 ->
          pk    = record["pk"]
          event = record["event"]
          op    = to_string(change[:kind])

          template_sql = record["template_sql"]
          template_key = record["template_key"]
          sub_hash     = record["sub_hash"]

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

              is_nil(template_sql) or is_nil(template_key) or is_nil(sub_hash) ->
                false

              MapSet.size(sub_route_set) == 0 ->
                false

              true ->
                field = record["table_field"]
                type  = change.columnNameTypes[field]
                eqop  = record["equality"]
                left_raw = change.columnValueName[field]

                case Utils.type_family(type) do
                  :number  -> Utils.eval_value_or_set(:number,  eqop, left_raw, sub_route_set)
                  :boolean -> Utils.eval_value_or_set(:boolean, eqop, left_raw, sub_route_set)
                  :date    -> Utils.eval_value_or_set(:date,    eqop, left_raw, sub_route_set)
                  :uuid    -> Utils.eval_value_or_set(:uuid,    eqop, left_raw, sub_route_set)
                  :text    -> Utils.eval_value_or_set(:text,    eqop, left_raw, sub_route_set)
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
                sub_hashes: MapSet.new([to_string(sub_hash)]),
                ids: [pk_value],
                pk: pk,
                alias: record["alias"]
              },
              fn existing ->
                existing
                |> Map.put(:database_op, op) # last op wins for the batch key
                |> Map.update!(:sub_hashes, fn set ->
                  MapSet.put(set, to_string(sub_hash))
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
end
