require "./spec_helper"

module PlaceOS::Source
  describe StatusEvents do
    it "passes status events to PublisherManager" do
      module_id = "mod-hello_hello"
      status_key = "power"
      mock_mappings_state = mock_state(module_id: module_id)

      mock_mappings = Mappings.new(mock_mappings_state)
      mock_publisher_manager = MockManager.new
      managers : Array(PlaceOS::Source::PublisherManager) = [mock_publisher_manager] of PlaceOS::Source::PublisherManager

      events = StatusEvents.new(mock_mappings, managers)
      spawn { events.start }

      sleep 1000.milliseconds

      Redis.open(url: REDIS_URL) do |client|
        client.publish("status/#{module_id}/#{status_key}", expected_payload("on"))
      end

      sleep 1000.milliseconds

      message = mock_publisher_manager.messages.first?
      message.should_not be_nil
      message = message.not_nil!

      key = MqttPublisher.generate_key(message.data)

      key.should eq "placeos/org-donor/state/_/cards/nek/2042/cs-9445/12345/M'Odule/1/#{status_key}"
      message.payload.should eq expected_payload("on")
      events.stop
    end

    it "overwrites and keep only a single copy of unprocessed event" do
      module_id = "mod-hello_hello"
      status_key = "power"
      mock_mappings_state = mock_state(module_id: module_id)

      mock_mappings = Mappings.new(mock_mappings_state)
      mock_publisher_manager = MockManager.new
      managers : Array(PlaceOS::Source::PublisherManager) = [mock_publisher_manager] of PlaceOS::Source::PublisherManager

      events = StatusEvents.new(mock_mappings, managers)
      spawn { events.start }

      sleep 1000.milliseconds

      Redis.open(url: REDIS_URL) do |client|
        client.publish("status/#{module_id}/#{status_key}", expected_payload("on"))
        client.publish("status/#{module_id}/#{status_key}", expected_payload("off"))
      end

      sleep 100.milliseconds
      mock_publisher_manager.messages.size.should eq(1)
      message = mock_publisher_manager.messages.first?
      message.should_not be_nil
      message = message.not_nil!
      message.payload.should eq expected_payload("off")
    end
  end
end
