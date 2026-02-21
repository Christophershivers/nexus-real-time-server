defmodule NexusRealtimeServer.PayloadParser do
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
end
