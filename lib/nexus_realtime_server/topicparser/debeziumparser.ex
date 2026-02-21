defmodule NexusRealtimeServer.DebeziumParser do
  def debeziumPayLoadParser(messages) do
    messages
    |> List.wrap()
    |> Enum.map(fn msg ->
      schema = msg["schema"] || %{}
      schema_fields = schema["fields"] || []
      raw_payload = msg["payload"] || %{}

      op = Map.get(raw_payload, "__op")

      kind =
        case op do
          "c" -> "insert"
          "u" -> "update"
          "d" -> "delete"
          "r" -> "snapshot"
          _ -> nil
        end

      payload = Map.delete(raw_payload, "__op")

      table =
        case schema["name"] do
          nil ->
            "unknown"

          name ->
            parts = String.split(name, ".")
            if length(parts) >= 2, do: Enum.at(parts, -2), else: List.last(parts)
        end

      column_names =
        schema_fields
        |> Enum.map(& &1["field"])
        |> Enum.reject(&(&1 == "__op"))

      column_types =
        schema_fields
        |> Enum.reject(&(&1["field"] == "__op"))
        |> Enum.map(& &1["type"])

      fields =
        schema_fields
        |> Enum.reject(&(&1["field"] == "__op"))
        |> Map.new(fn f -> {f["field"], f["type"]} end)

      column_values =
        Enum.map(column_names, fn name ->
          Map.get(payload, name)
        end)

      %{
        kind: kind,
        table: table,
        columnNames: List.to_tuple(column_names),
        columnTypes: List.to_tuple(column_types),
        columnValues: List.to_tuple(column_values),
        columnNameTypes: fields,
        columnValueName: payload
      }
    end)
  end
end
