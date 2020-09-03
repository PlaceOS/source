require "../spec_helper"

module PlaceOS::Source
  describe MqttBrokerManager do
    it "creates MQTT publishing clients" do
      model = Model::Broker.new(
        name: "mosquitto",
        host: "localhost",
        port: 1883,
      )
      id = "broker-acabsns"
      model.id = id

      event = {action: Resource::Action::Created, resource: model}
      publisher_manager = MqttBrokerManager.new
      publisher_manager.@event_channel.send(event)
      publisher_manager.start

      # Yield to the PublisherManager
      while publisher_manager.processed.size != 1
        Fiber.yield
      end

      publisher = publisher_manager.@publishers[id]?
      publisher.should_not be_nil
    end
  end
end
