defmodule NexusRealtimeServer.Main do
  alias NexusRealtimeServer.InMemoryTopicParser
  alias NexusRealtimeServer.FetchQueries

  def main(payload) do
    IO.inspect(payload, lebel: "payload data")
    queries = InMemoryTopicParser.parse(payload)
    IO.inspect(queries, label: "In Main module")
    FetchQueries.run(queries)
  end
end
