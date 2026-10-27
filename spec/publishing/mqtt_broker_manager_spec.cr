require "../spec_helper"

module PlaceOS::Source
  describe MqttBrokerManager do
    it "creates MQTT publishing clients" do
      model = test_broker

      event = Resource::Event(PlaceOS::Model::Broker).new(:created, model)
      publisher_manager = MqttBrokerManager.new
      publisher_manager.@event_channel.send(event)
      publisher_manager.start

      # Yield to the PublisherManager
      while publisher_manager.processed.empty?
        sleep 100.milliseconds
      end

      publisher = publisher_manager.@publishers[model.id.as(String)]?
      publisher.should_not be_nil
    ensure
      # NOTE:: a manager left running acts on every Broker later specs save,
      # and its publishers take their sessions over
      publisher_manager.try &.stop
      publisher_manager.try &.publishers.each(&.stop)
    end
  end
end
