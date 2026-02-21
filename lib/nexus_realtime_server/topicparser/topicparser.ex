defmodule NexusRealtimeServer.TopicParser do

  alias NexusRealtimeServer.WorkItems
  alias NexusRealtimeServer.AllTopics
  alias NexusRealtimeServer.RecordTopic
  alias NexusRealtimeServer.DebeziumParser

  def parse(payload) do
    IO.inspect(payload, label: "Raw payload in InMemoryTopicParser.parse")
    parsed_changes = DebeziumParser.debeziumPayLoadParser(payload)
    IO.inspect(parsed_changes, label: "Parsed changes in InMemoryTopicParser.parse")
    all_topics = AllTopics.getAllTopics(parsed_changes)
    records_by_topic = RecordTopic.getRecordsByTopic(all_topics)
    WorkItems.buildWorkItems(records_by_topic, parsed_changes)
  end

end
