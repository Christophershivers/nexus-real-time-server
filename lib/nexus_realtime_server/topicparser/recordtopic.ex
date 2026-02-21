defmodule NexusRealtimeServer.RecordTopic do
  def getRecordsByTopic(allTopics) do
    allTopics
    |> Enum.uniq()
    |> Enum.flat_map(fn topic ->
      # dirty_index_read by :topic (attribute 2 in your attrs list)
      rows = :mnesia.dirty_index_read(:realtime_query, topic, 3)

      Enum.map(rows, fn {:realtime_query, rec_id, topic2, _userid, record_map} ->
        {topic2, Map.put(record_map, "__rec_id", rec_id)}
      end)
    end)
  end
end
