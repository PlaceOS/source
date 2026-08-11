require "../spec_helper"
require "placeos-driver/storage"

module PlaceOS::Source
  # The module name and index are both topic segments, so changing either moves
  # every status the Module publishes. Because everything is retained, the old
  # topic keeps serving its last value forever unless it is cleared — a
  # consumer would see state for a path nothing publishes to any more.
  # Builds mappings for one module in one system, with a hierarchy it can
  # actually resolve a topic from
  def self.mapped(module_id : String, name : String, index : Int32, org : String) : Mappings
    state = Mappings::State.new
    state.drivers[module_id] = "driver-1234"
    state.system_modules[module_id] = [{name: name, control_system_id: "cs-1", index: index}]
    state.system_zones["cs-1"] = {"org" => org, "building" => "b", "level" => "l", "area" => "a"}
    Mappings.new(state)
  end

  def self.topic_for(mappings : Mappings, module_id : String, status : String) : String
    event = mappings.status_events?(module_id, status).not_nil!.first
    MqttPublisher.generate_key(event).not_nil!
  end

  # Publishes a status, moves the Module, and reports what the broker holds
  # at each path afterwards
  def self.move(index : Int32, new_name : String, new_index : Int32)
    module_id = "mod-#{UUID.random}"
    org = "org-#{UUID.random}"
    status = "power"

    # the Module's stored state, which is where the statuses to clear come from
    store = PlaceOS::Driver::RedisStorage.new(module_id)
    store[status] = "true"

    mappings = mapped(module_id, "Old Name", index, org)
    old_topic = topic_for(mappings, module_id, status)

    broker = PlaceOS::Source.isolated_broker
    publisher = MqttPublisher.new(broker)
    manager = MockBrokerManager.new(publisher)
    router = Router::Module.new(mappings, [manager] of PublisherManager)

    begin
      publisher.start

      # state as it was, under the old path
      publisher.publish(Publisher::Message.new(
        mappings.status_events?(module_id, status).not_nil!.first, "true", Time.utc))
      sleep 300.milliseconds

      # the rename: clear what is there, then rewrite the mapping
      router.remove_retained_state(module_id)
      mappings.set_system_modules("cs-1", {
        module_id => {name: new_name, control_system_id: "cs-1", index: new_index},
      })
      new_topic = topic_for(mappings, module_id, status)

      # republish at the new path, which is what a resync does
      publisher.message_queue.send(Publisher::Message.new(
        mappings.status_events?(module_id, status).not_nil!.first, "true", Time.utc))
      sleep 800.milliseconds

      {old_topic, new_topic}
    ensure
      publisher.stop rescue nil
      store.clear rescue nil
    end
  end

  def self.retained_at(topic : String) : String?
    client = PlaceOS::Source.subscriber
    begin
      messages = PlaceOS::Source.subscribe_channel(client, topic)
      select
      when message = messages.receive
        message[1]
      when timeout(3.seconds)
        nil
      end
    ensure
      client.disconnect rescue nil
    end
  end

  describe "renaming a Module" do
    it "moves the retained value to the new topic on rename" do
      old_topic, new_topic = PlaceOS::Source.move(1, "New Name", 1)
      old_topic.should_not eq new_topic

      # the value now lives at the new path
      payload = PlaceOS::Source.retained_at(new_topic)
      payload.should_not be_nil
      JSON.parse(payload.to_s)["value"].should be_true

      # and nothing is left behind at the old one
      PlaceOS::Source.retained_at(old_topic).should be_nil
    end

    it "moves the retained value to the new topic on an index change" do
      old_topic, new_topic = PlaceOS::Source.move(1, "Old Name", 2)
      old_topic.should_not eq new_topic
      old_topic.should end_with "/1/power"
      new_topic.should end_with "/2/power"

      payload = PlaceOS::Source.retained_at(new_topic)
      payload.should_not be_nil
      JSON.parse(payload.to_s)["value"].should be_true

      PlaceOS::Source.retained_at(old_topic).should be_nil
    end
  end
end
