require "../spec_helper"

module PlaceOS::Ingest
  def self.mock_zones
    Mappings.hierarchy.map_with_index do |tag, idx|
      zone = Model::Generator.zone
      zone.tags = Set{tag}
      zone.id = "zone-#{idx}"
      zone
    end
  end

  def self.mock_modules(names)
    driver = Model::Generator.driver(module_name: "mock")
    driver.id = "driver-sns"

    names.map_with_index do |name, idx|
      mod = Model::Generator.module(driver)
      mod.custom_name = name
      mod.id = "mod-#{idx}"
      mod
    end
  end

  describe Router::ControlSystem do
    it "system_modules" do
      cs = Model::Generator.control_system
      cs.id = "cs-1245"
      modules = mock_modules(["custom", nil, "custom", "extra_custom", nil])
      cs.modules = modules.compact_map &.id

      Router::ControlSystem.system_modules(cs, modules).should eq ({
        "mod-0" => {
          name:              "custom",
          control_system_id: "cs-1245",
          index:             1,
        },
        "mod-1" => {
          name:              "mock",
          control_system_id: "cs-1245",
          index:             1,
        },
        "mod-2" => {
          name:              "custom",
          control_system_id: "cs-1245",
          index:             2,
        },
        "mod-3" => {
          name:              "extra_custom",
          control_system_id: "cs-1245",
          index:             1,
        },
        "mod-4" => {
          name:              "mock",
          control_system_id: "cs-1245",
          index:             2,
        },
      })
    end

    it "system_zones" do
      cs = Model::Generator.control_system
      cs.id = "cs-1245"
      zones = mock_zones
      cs.zones = zones.compact_map &.id
      Router::ControlSystem.system_zones(cs, zones).should eq ({
        "org"      => "zone-0",
        "building" => "zone-1",
        "level"    => "zone-2",
        "area"     => "zone-3",
      })
    end
  end
end
