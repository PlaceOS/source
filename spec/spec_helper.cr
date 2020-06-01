require "spec"
require "models/spec/generator"

require "../src/placeos-mqtt"

module PlaceOS::MQTT
  class MockManager < PublisherManager
    getter messages : Array(Publisher::Metadata | Publisher::State) = [] of Publisher::Metadata | Publisher::State

    def broadcast(message)
      messages << message
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
