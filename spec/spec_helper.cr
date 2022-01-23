require "../src/config"

require "spec"
require "placeos-models/spec/generator"

require "../src/placeos-source"
require "../src/source/*"

Spec.before_suite do
  PlaceOS::Model::Broker.clear
  ::Log.setup "*", :trace, PlaceOS::LogBackend.log_backend
end

def expected_payload(value)
  %({"time":0,"value":#{value.to_json}})
end

def test_broker
  existing = PlaceOS::Model::Broker.where(name: "mosquitto").first?
  return existing if existing

  PlaceOS::Model::Broker.new(
    name: "mosquitto",
    host: ENV["MQTT_HOST"]?.presence || "localhost",
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

  class MockManager
    include PublisherManager

    getter messages : Array(Publisher::Message) = [] of Publisher::Message

    def broadcast(message : Publisher::Message)
      messages << message
    end

    def start
    end

    def stop
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
    org_id = "org-donor"
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
