defmodule NexusRealtimeServer.AllTopics do
  def getAllTopics(parsed_changes) when is_list(parsed_changes) do
    parsed_changes
    |> Enum.flat_map(fn %{table: table, columnNameTypes: name_types} ->
      Map.keys(name_types)
      |> Enum.map(fn field -> "#{table}:#{field}" end)
    end)
    |> Enum.uniq()
  end
end
