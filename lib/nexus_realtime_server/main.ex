defmodule NexusRealtimeServer.Main do
  alias NexusRealtimeServer.FetchQueries
  alias NexusRealtimeServer.TopicParser

  def main(payload) do
    queries = TopicParser.parse(payload)
    IO.inspect(queries, label: "Parsed queries in Main.main")
    FetchQueries.run(queries)
  end
end
