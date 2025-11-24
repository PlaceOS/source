require "./spec_helper"

module PlaceOS::Source
  describe "Broker State Sync" do
    it "callback is invoked when new broker is added after startup" do
      # Create initial broker
      test_broker

      # Setup MQTT broker manager
      mqtt_manager = MqttBrokerManager.new

      # Track if callback was invoked
      callback_invoked = false
      callback_broker_id = ""

      mqtt_manager.on_broker_ready = ->(broker_id : String) {
        callback_invoked = true
        callback_broker_id = broker_id
      }

      # Start the manager to mark startup as finished
      mqtt_manager.start

      # Wait for startup to complete
      sleep 200.milliseconds

      # Create a new broker after startup
      new_broker = PlaceOS::Model::Broker.new(
        name: "new-broker-#{Time.utc.to_unix}",
        host: ENV["MQTT_HOST"]?.presence || "mqtt",
        port: ENV["MQTT_PORT"]?.presence.try(&.to_i?) || 1883,
        auth_type: :no_auth,
      ).save!

      # Trigger the broker creation event
      event = Resource::Event(PlaceOS::Model::Broker).new(:created, new_broker)
      mqtt_manager.@event_channel.send(event)

      # Wait for broker to be processed
      sleep 300.milliseconds

      # Verify the broker was created successfully
      mqtt_manager.@publishers[new_broker.id.as(String)]?.should_not be_nil

      # Verify the callback was invoked
      callback_invoked.should be_true
      callback_broker_id.should eq new_broker.id.as(String)

      # Cleanup
      mqtt_manager.stop
      new_broker.destroy
    end

    it "callback is not invoked for brokers created during startup" do
      # Setup MQTT broker manager
      mqtt_manager = MqttBrokerManager.new

      # Track if callback was invoked
      callback_invoked = false

      mqtt_manager.on_broker_ready = ->(_broker_id : String) {
        callback_invoked = true
      }

      # Create broker before starting (simulating existing broker)
      startup_broker = test_broker

      # Start the manager (this will load existing brokers)
      mqtt_manager.start

      # Wait for startup to complete
      sleep 200.milliseconds

      # Verify the broker was loaded
      mqtt_manager.@publishers[startup_broker.id.as(String)]?.should_not be_nil

      # Verify the callback was NOT invoked during startup
      callback_invoked.should be_false

      # Cleanup
      mqtt_manager.stop
    end

    it "resync_state only runs after initial sync completes" do
      mock_mappings_state = mock_state(module_id: "mod-test")
      mock_mappings = Mappings.new(mock_mappings_state)
      mock_publisher = MockManager.new

      status_events = StatusEvents.new(mock_mappings, [mock_publisher] of PublisherManager)

      # Before initial sync, resync should not run
      status_events.resync_state
      mock_publisher.messages.size.should eq 0

      # Start to trigger initial sync
      spawn { status_events.start }

      # Wait for initial sync
      sleep 300.milliseconds

      # Clear messages from initial sync
      mock_publisher.messages.clear

      # Now resync should work
      status_events.resync_state

      # Wait for resync to process
      sleep 200.milliseconds

      # Cleanup
      status_events.stop
    end

    it "full integration: new broker receives state via resync" do
      # Create initial broker
      test_broker

      # Setup mock publisher to track messages
      mock_publisher = MockManager.new
      publisher_managers = [mock_publisher] of PublisherManager

      # Add MQTT broker manager
      mqtt_manager = MqttBrokerManager.new
      publisher_managers << mqtt_manager

      # Mock data with a module that has proper mappings
      module_id = "mod-integration-test"
      status_key = "power"
      mock_mappings_state = mock_state(module_id: module_id)
      mock_mappings = Mappings.new(mock_mappings_state)

      # Start application manager
      manager = Manager.new(publisher_managers, mock_mappings)
      manager.start

      # Wait for initial sync to complete
      sleep 300.milliseconds

      # Store module state in Redis
      Redis.open(url: REDIS_URL) do |client|
        client.set("status/#{module_id}/#{status_key}", "on".to_json)
      end

      # Clear any messages from initial sync
      mock_publisher.messages.clear

      # Create a new broker after startup
      new_broker = PlaceOS::Model::Broker.new(
        name: "integration-broker-#{Time.utc.to_unix}",
        host: ENV["MQTT_HOST"]?.presence || "mqtt",
        port: ENV["MQTT_PORT"]?.presence.try(&.to_i?) || 1883,
        auth_type: :no_auth,
      ).save!

      # Trigger the broker creation event
      event = Resource::Event(PlaceOS::Model::Broker).new(:created, new_broker)
      mqtt_manager.@event_channel.send(event)

      # Wait for broker to be processed and state resync to occur
      sleep 500.milliseconds

      # Verify the broker was created
      mqtt_manager.@publishers[new_broker.id.as(String)]?.should_not be_nil

      # Verify the callback was wired up by the manager
      mqtt_manager.on_broker_ready.should_not be_nil

      # Cleanup
      manager.stop
      new_broker.destroy
    end
  end
end
