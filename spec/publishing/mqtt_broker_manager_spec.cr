require "../spec_helper"

module PlaceOS::Source
  describe MqttBrokerManager do
    it "creates MQTT publishing clients" do
      model = test_broker
      id = "broker-acabsns"
      model.id = id

      event = Resource::Event.new(:created, model)
      publisher_manager = MqttBrokerManager.new
      publisher_manager.@event_channel.send(event)
      publisher_manager.start

      # Yield to the PublisherManager
      while publisher_manager.processed.empty?
        # My guess if its forever looping here its because the creation of a mqtt is blocking
        # this then blocks IO somewhere
        sleep 100.milliseconds
      end

      publisher = publisher_manager.@publishers[id]?
      publisher.should_not be_nil
    end
  end
end
