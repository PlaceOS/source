require "../spec_helper"

module PlaceOS::Source
  # Builds a status event and its MQTT topic under a scope unique to the caller.
  #
  # NOTE:: the org id has to vary too, not just the module. Retained messages
  # live in the broker until something replaces them, so a shared scope means a
  # wildcard subscription picks up whatever earlier examples — or earlier runs
  # against the same container — left behind
  def self.unique_status_event(org_id : String = "org-#{UUID.random}")
    module_id = UUID.random.to_s
    state = mock_state(
      module_id: module_id,
      index: 5,
      module_name: "M'Odule",
      driver_id: "12345",
      control_system_id: "cs-#{UUID.random}",
      area_id: "2042",
      level_id: "nek",
      building_id: "cards",
      org_id: org_id,
    )

    event = Mappings.new(state).status_events?(module_id, "power").not_nil!.first
    {event, MqttPublisher.generate_key(event).not_nil!}
  end

  # A Broker of its own per example, deliberately **not** persisted.
  #
  # Two reasons. The publisher connects with the broker id as its MQTT client
  # id, so examples sharing one take each other's session over — and a client
  # that has been taken over stays down, by design.
  #
  # Saving it would swap that problem for a worse one: `MqttBrokerManager` is a
  # `Resource(Model::Broker)`, so any manager still running from an earlier spec
  # reacts to the new row, builds its own publisher for it, and takes the
  # session over from underneath us
  def self.isolated_broker : PlaceOS::Model::Broker
    shared = test_broker
    broker = PlaceOS::Model::Broker.new(
      name: "spec-#{UUID.random}",
      host: shared.host,
      port: shared.port,
      auth_type: :no_auth,
    )
    broker.id = "spec-broker-#{UUID.random}"
    broker
  end

  # Runs a block with a publisher on its own broker, cleaning both up after
  def self.with_publisher(&)
    broker = isolated_broker
    publisher = MqttPublisher.new(broker)
    begin
      yield publisher
    ensure
      publisher.stop rescue nil
    end
  end

  # A bare client against the same broker, standing in for anything else that
  # consumes the state we publish
  def self.subscriber(broker = test_broker) : ::MQTT::Client
    client = ::MQTT::Client.new do
      ::MQTT::Transport::TCP.new(host: broker.host, port: broker.port).as(::MQTT::Transport)
    end
    client.connect(client_id: "spec-subscriber-#{UUID.random}")
    client
  end

  # Subscribes and hands back a channel of everything that arrives
  def self.subscribe_channel(client, topic) : Channel(Tuple(String, String, Bool))
    received = Channel(Tuple(String, String, Bool)).new(16)
    client.subscribe(topic) do |key, payload, retained|
      received.send({key, String.new(payload), retained})
      nil
    end
    received
  end

  def self.take(received, topic, timeout = 10.seconds)
    select
    when message = received.receive
      message
    when timeout(timeout)
      raise "timed out waiting for a message on #{topic}"
    end
  end

  def self.collect(client, topic, count = 1, timeout = 10.seconds)
    received = subscribe_channel(client, topic)
    Array(Tuple(String, String, Bool)).new(count) { take(received, topic, timeout) }
  end

  describe MqttPublisher do
    describe "connection" do
      it "negotiates a protocol version with the broker" do
        PlaceOS::Source.with_publisher do |publisher|
          publisher.protocol_version.should_not be_nil
          publisher.client.closed?.should be_false
        end
      end

      # stop used to wait for the connection to close before asking it to,
      # which blocked until the broker gave up on us
      it "stops without hanging" do
        publisher = MqttPublisher.new(PlaceOS::Source.isolated_broker)
        publisher.start

        done = Channel(Nil).new(1)
        spawn do
          publisher.stop
          done.send(nil)
        end

        select
        when done.receive
          publisher.client.closed?.should be_true
        when timeout(10.seconds)
          fail "stop did not return"
        end
      end
    end

    describe "#publish" do
      it "writes a status event to its MQTT topic" do
        client = PlaceOS::Source.subscriber
        status_event, key = PlaceOS::Source.unique_status_event

        begin
          # subscribe first, so this is a live delivery rather than a retained one
          messages = PlaceOS::Source.subscribe_channel(client, key)
          sleep 200.milliseconds

          PlaceOS::Source.with_publisher do |publisher|
            publisher.publish(Publisher::Message.new(status_event, "true", timestamp: Time.utc))
          end

          topic, payload, _retained = PlaceOS::Source.take(messages, key)
          topic.should eq key
          JSON.parse(payload)["value"].should be_true
        ensure
          client.disconnect rescue nil
        end
      end
    end

    # The reason source publishes with `retain: true`: a consumer that connects
    # later needs the current state of every status, not just what changes from
    # then on. The broker holds it, so it has to outlive the connection that
    # published it
    describe "retained state" do
      it "delivers the last published value to a subscriber that connects later" do
        status_event, key = PlaceOS::Source.unique_status_event

        PlaceOS::Source.with_publisher do |publisher|
          publisher.publish(Publisher::Message.new(status_event, "true", timestamp: Time.utc))
          sleep 300.milliseconds
        end

        # an entirely separate connection, established after the publisher went away
        client = PlaceOS::Source.subscriber
        begin
          topic, payload, retained = PlaceOS::Source.collect(client, key).first
          topic.should eq key
          JSON.parse(payload)["value"].should be_true
          # flagged retained, so a consumer can tell stored state from a live update
          retained.should be_true
        ensure
          client.disconnect rescue nil
        end
      end

      it "keeps only the most recent value for a status" do
        status_event, key = PlaceOS::Source.unique_status_event

        PlaceOS::Source.with_publisher do |publisher|
          publisher.publish(Publisher::Message.new(status_event, "false", timestamp: Time.utc))
          sleep 100.milliseconds
          publisher.publish(Publisher::Message.new(status_event, "true", timestamp: Time.utc))
          sleep 300.milliseconds
        end

        client = PlaceOS::Source.subscriber
        begin
          _topic, payload, retained = PlaceOS::Source.collect(client, key).first
          JSON.parse(payload)["value"].should be_true
          retained.should be_true
        ensure
          client.disconnect rescue nil
        end
      end

      it "retains state published through the message queue" do
        status_event, key = PlaceOS::Source.unique_status_event

        PlaceOS::Source.with_publisher do |publisher|
          publisher.start
          publisher.message_queue.send(Publisher::Message.new(status_event, %("online"), timestamp: Time.utc))
          sleep 500.milliseconds
        end

        client = PlaceOS::Source.subscriber
        begin
          _topic, payload, retained = PlaceOS::Source.collect(client, key).first
          JSON.parse(payload)["value"].should eq "online"
          retained.should be_true
        ensure
          client.disconnect rescue nil
        end
      end

      it "retains metadata as well as state" do
        metadata_event = Mappings::Metadata.new("mod-#{UUID.random}", "hello")
        key = MqttPublisher.generate_key(metadata_event).not_nil!

        PlaceOS::Source.with_publisher do |publisher|
          publisher.publish(Publisher::Message.new(metadata_event, %({"name":"thing"}), timestamp: Time.utc))
          sleep 300.milliseconds
        end

        client = PlaceOS::Source.subscriber
        begin
          _topic, payload, retained = PlaceOS::Source.collect(client, key).first
          JSON.parse(payload)["value"]["name"].should eq "thing"
          retained.should be_true
        ensure
          client.disconnect rescue nil
        end
      end

      it "delivers every retained status under a wildcard subscription" do
        # both under one scope, which nothing else in the suite publishes to
        org = "org-#{UUID.random}"
        first_event, first_key = PlaceOS::Source.unique_status_event(org)
        second_event, second_key = PlaceOS::Source.unique_status_event(org)

        PlaceOS::Source.with_publisher do |publisher|
          publisher.publish(Publisher::Message.new(first_event, "true", timestamp: Time.utc))
          publisher.publish(Publisher::Message.new(second_event, "false", timestamp: Time.utc))
          sleep 300.milliseconds
        end

        client = PlaceOS::Source.subscriber
        begin
          # the scope both keys share, which is how a consumer subscribes in anger
          scope = first_key.split('/')[0, 3].join('/')
          messages = PlaceOS::Source.collect(client, "#{scope}/#", count: 2)

          messages.map(&.[](2)).should eq [true, true]
          keys = messages.map(&.[](0))
          keys.should contain first_key
          keys.should contain second_key
        ensure
          client.disconnect rescue nil
        end
      end
    end

    # A topic only holds the current value, so when a Module moves or goes away
    # the value it left behind is a ghost: consumers keep reading state for
    # something that no longer publishes there
    describe "removing retained state" do
      it "clears the retained value for a key" do
        status_event, key = PlaceOS::Source.unique_status_event

        PlaceOS::Source.with_publisher do |publisher|
          publisher.publish(Publisher::Message.new(status_event, "true", timestamp: Time.utc))
          sleep 200.milliseconds
          publisher.delete(Publisher::Message.new(status_event, nil, timestamp: Time.utc))
          sleep 300.milliseconds
        end

        client = PlaceOS::Source.subscriber
        begin
          messages = PlaceOS::Source.subscribe_channel(client, key)
          select
          when leftover = messages.receive
            fail "retained value should have been removed, got #{leftover.inspect}"
          when timeout(3.seconds)
            # nothing retained, which is the pass condition
          end
        ensure
          client.disconnect rescue nil
        end
      end
    end

    describe "keys" do
      it "creates a state event topic" do
        state = mock_state(
          module_id: "mod-1234",
          index: 1,
          module_name: "M'Odule",
          driver_id: "12345",
          control_system_id: "cs-9445",
          area_id: "2042",
          level_id: "nek",
          building_id: "cards",
          org_id: "org-donor",
        )

        status_event = Mappings.new(state).status_events?("mod-1234", "power").not_nil!.first
        key = MqttPublisher.generate_key(status_event)
        key.should_not be_nil
        key.not_nil!.should eq "placeos/org-donor/state/_/cards/nek/2042/cs-9445/12345/M'Odule/1/power"
      end

      it "doesn't create topics for Modules without a top-level scope Zone" do
        state = mock_state(module_id: "mod-1234", control_system_id: "cs-id")

        # Remove the top level scope mapping
        state.system_zones["cs-id"].delete(Mappings.scope)

        status_event = Mappings.new(state).status_events?("mod-1234", "power").not_nil!.first

        MqttPublisher.generate_key(status_event).should be_nil
      end

      it "replaces missing hierarchy Zone ids with a placeholder" do
        state = mock_state(
          module_id: "mod-1234",
          index: 1,
          module_name: "M'Odule",
          driver_id: "12345",
          control_system_id: "cs-9445",
          area_id: "2042",
          level_id: "nek",
          org_id: "org-donor",
        )

        state.system_zones["cs-9445"].delete("building")

        status_event = Mappings.new(state).status_events?("mod-1234", "power").not_nil!.first

        key = MqttPublisher.generate_key(status_event)
        key.should_not be_nil
        key.not_nil!.should eq "placeos/org-donor/state/_/_/nek/2042/cs-9445/12345/M'Odule/1/power"
      end

      it "generates a metadata key" do
        metadata_event = Mappings::Metadata.new("mod-1234", "hello")
        key = MqttPublisher.generate_key(metadata_event).not_nil!
        key.should eq "placeos/hello/metadata/mod-1234"
      end
    end

    describe "payloads" do
      it "non-empty" do
        JSON.parse(MqttPublisher.payload(%("hello"), nil, Time.utc))["value"].raw.should eq "hello"
      end

      it "empty payload metadata" do
        JSON.parse(MqttPublisher.payload(nil, nil, Time.utc))["value"].raw.should be_nil
      end
    end
  end
end
