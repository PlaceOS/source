require "./spec_helper"

module PlaceOS::Source
  describe Manager do
    it "provides concurrent publication to several stores" do
      # Create a test broker
      test_broker

      publisher_managers = [] of PublisherManager

      publisher_managers << MqttBrokerManager.new

      influx_host, influx_api_key = INFLUX_HOST.not_nil!, INFLUX_API_KEY.not_nil!

      publisher_managers << InfluxManager.new(influx_host, influx_api_key)

      mock_publisher = MockManager.new

      publisher_managers << mock_publisher

      # Mock data
      module_id = "mod-hello_hello"
      status_key = "power"
      mock_mappings_state = mock_state(module_id: module_id)
      mock_mappings = Mappings.new(mock_mappings_state)

      # Start application manager
      manager = Manager.new(publisher_managers, mock_mappings)
      manager.start

      sleep 50.milliseconds

      Redis.open(url: REDIS_URL) do |client|
        client.publish("status/#{module_id}/#{status_key}", "on".to_json)
      end

      sleep 50.milliseconds

      message = begin
        Retriable.retry(max_attempts: 5, base_interval: 20.milliseconds) do
          # Wait for a message to be published
          mock_publisher.messages.first?.tap { |m| raise "retry" if m.nil? }
        end
      rescue
        nil
      end

      message.should_not be_nil

      manager.stop
    end

    describe "resync" do
      it "runs one at a time" do
        manager = Manager.new([] of PublisherManager)
        manager.resync_status.state.idle?.should be_true

        # never started, so it waits on the initial sync and stays running
        manager.resync(clear: true).should be_true
        manager.resync.should be_false
        status = manager.resync_status
        status.state.clearing?.should be_true
        status.clear?.should be_true
        status.started_at.should_not be_nil
      end
    end
  end
end
