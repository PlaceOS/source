require "./spec_helper"

module PlaceOS::MQTT
  describe StatusEvents do
    it "passes status events to PublisherManager" do
      module_id = "mod-hello_hello"
      status_key = "power"
      mock_mappings_state = mock_state(module_id: module_id)

      mock_mappings = Mappings.new(mock_mappings_state)
      mock_publisher_manager = MockManager.new

      events = StatusEvents.new(mock_mappings, mock_publisher_manager)
      spawn(same_thread: true) { events.start }

      sleep 0.1

      Redis.open(url: ENV["REDIS_URL"]?) do |client|
        client.publish("status/#{module_id}/#{status_key}", "on".to_json)
      end

      sleep 0.1

      message = mock_publisher_manager.messages.first?
      message.should_not be_nil
      message = message.not_nil!
      message.key.should eq "placeos/org-donor/state/cards/nek/2042/cs-9445/12345/M'Odule/1/#{status_key}"
      message.payload.should eq expected_payload("on")

      events.stop
    end
  end
end
