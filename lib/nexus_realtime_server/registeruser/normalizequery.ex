defmodule NexusRealtimeServer.NormalizeQuery do
  def normalize_route_values_set(v) when is_list(v) do
    v
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  def normalize_route_values_set(%MapSet{} = set) do
    set
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  def normalize_route_values_set(nil), do: MapSet.new()

  def normalize_route_values_set(v) do
    s = v |> to_string() |> String.trim()
    if s == "", do: MapSet.new(), else: MapSet.new([s])
  end

end
