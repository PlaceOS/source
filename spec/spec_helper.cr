require "../src/config"

require "spec"
require "placeos-models/spec/generator"

require "../src/placeos-source"
require "../src/source/*"

PgORM::Database.configure { |_| }
Spec.before_suite do
  PlaceOS::Model::Broker.clear
  ::Log.setup "*", :info, PlaceOS::LogBackend.log_backend
end

def expected_payload(value)
  %({"time":0,"value":#{value.to_json}})
end

def test_broker
  existing = PlaceOS::Model::Broker.where(name: "mosquitto").first?
  return existing if existing

  PlaceOS::Model::Broker.new(
    name: "mosquitto",
    host: ENV["MQTT_HOST"]?.presence || "mqtt",
    port: ENV["MQTT_PORT"]?.presence.try &.to_i? || 1883,
    auth_type: :no_auth,
  ).save!
end

module PlaceOS::Source
  abstract class Publisher
    # Mock the timestamp
    def self.timestamp : Time
      Time::UNIX_EPOCH
    end
  end

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

  # Wraps a single publisher, so a router's deletions reach a real broker
  class MockBrokerManager
    include PublisherManager

    def initialize(@publisher : Publisher)
    end

    def broadcast(message : Publisher::Message)
      @publisher.message_queue.send(message)
    end

    def broadcast_delete(message : Publisher::Message)
      @publisher.queue_delete(message)
    end

    def deletes_pending? : Bool
      @publisher.deletes_pending?
    end

    def start
    end

    def stop
    end

    def stats : Hash(String, UInt64)
      {} of String => UInt64
    end
  end

  class MockManager
    include PublisherManager

    getter messages : Array(Publisher::Message) = [] of Publisher::Message

    # Keys whose retained value was queued for removal
    getter deletions : Array(Publisher::Message) = [] of Publisher::Message

    def broadcast(message : Publisher::Message)
      messages << message
    end

    def broadcast_delete(message : Publisher::Message)
      deletions << message
    end

    def deletes_pending? : Bool
      false
    end

    def start
    end

    def stop
    end

    def stats : Hash(String, UInt64)
      {"Mock" => messages.size.to_u64}
    end
  end

  def self.mock_state(
    module_id = "mod-1234",
    index = 1,
    module_name = "M'Odule",
    driver_id = "12345",
    control_system_id = "cs-9445",
    area_id = "2042",
    level_id = "nek",
    building_id = "cards",
    org_id = "org-donor",
  )
    state = Mappings::State.new
    state.system_modules[module_id] = [{name: module_name, control_system_id: control_system_id, index: index}]
    state.drivers[module_id] = driver_id
    state.system_zones[control_system_id] = {
      "area"     => area_id,
      "level"    => level_id,
      "building" => building_id,
      "org"      => org_id,
    }

    state
  end
end
