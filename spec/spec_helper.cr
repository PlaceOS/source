require "spec"
require "placeos-models/spec/generator"

require "../src/placeos-source"
require "../src/source/*"

def expected_payload(value)
  %({"time":0,"value":#{value.to_json}})
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

    def broadcast(message)
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
