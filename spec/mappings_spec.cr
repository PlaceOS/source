require "./spec_helper"

module PlaceOS::Source
  describe Mappings do
    describe "status_events?" do
      it "generates data for status events" do
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

        mappings = Mappings.new(state)
        events = mappings.status_events?("mod-1234", "power")
        events.should_not be_nil
        event = events.not_nil!.first
        event.module_id.should eq "mod-1234"
        event.index.should eq 1
        event.module_name.should eq "M'Odule"
        event.driver_id.should eq "12345"
        event.control_system_id.should eq "cs-9445"

        event.zone_mapping["area"].should eq "2042"
        event.zone_mapping["level"].should eq "nek"
        event.zone_mapping["building"].should eq "cards"
        event.zone_mapping["org"].should eq "org-donor"
      end
    end

    describe "system modules" do
      it "keeps each system's modules apart" do
        mappings = Mappings.new
        mappings.set_system_modules("cs-1", {
          "mod-a" => {name: "Display", control_system_id: "cs-1", index: 1},
          "mod-b" => {name: "Display", control_system_id: "cs-1", index: 2},
        })
        mappings.set_system_modules("cs-2", {
          "mod-a" => {name: "Screen", control_system_id: "cs-2", index: 1},
        })

        mappings.modules_in_systems({"cs-1"}).should eq Set{"mod-a", "mod-b"}
        mappings.system_modules_for("cs-2").should eq({"mod-a" => {name: "Screen", control_system_id: "cs-2", index: 1}})

        # replacing a system's modules leaves the other system's alone
        mappings.set_system_modules("cs-1", {
          "mod-b" => {name: "Display", control_system_id: "cs-1", index: 1},
        })
        mappings.modules_in_systems({"cs-1"}).should eq Set{"mod-b"}
        mappings.read(&.system_modules["mod-a"]).should eq [{name: "Screen", control_system_id: "cs-2", index: 1}]

        mappings.remove_system_modules("cs-2")
        mappings.read(&.system_modules.has_key?("mod-a")).should be_false
        mappings.system_modules_for("cs-2").should be_empty
      end

      it "forgets a deleted module in every system" do
        mappings = Mappings.new
        mappings.set_system_modules("cs-1", {"mod-a" => {name: "Display", control_system_id: "cs-1", index: 1}})
        mappings.set_system_modules("cs-2", {"mod-a" => {name: "Display", control_system_id: "cs-2", index: 1}})

        mappings.write(&.unmap_module("mod-a"))

        mappings.modules_in_systems({"cs-1", "cs-2"}).should be_empty
        mappings.read(&.system_module_ids).should be_empty
      end
    end

    describe "hierarchy_zones" do
      it "gets scope zones for ControlSystem" do
        Model::ControlSystem.clear
        Model::Zone.clear

        good_zone = Model::Generator.zone
        good_zone.tags = Set{Mappings.scope, "good"}
        good_zone.save!
        bad_zone = Model::Generator.zone
        bad_zone.tags = Set{"bad", "really bad"}
        bad_zone.save!

        cs = Model::Generator.control_system
        cs.zones = [good_zone.id, bad_zone.id].compact
        cs.save!

        hierarchy_zones = Mappings.hierarchy_zones(cs)
        hierarchy_zones.size.should eq 1
        hierarchy_zones.first.id.should eq good_zone.id
      end

      it "gets scope zones for Driver" do
        Model::Module.clear
        Model::ControlSystem.clear
        Model::Zone.clear
        Model::Driver.clear

        good_zone = Model::Generator.zone
        good_zone.tags = Set{Mappings.scope, "good"}
        good_zone.save!
        bad_zone = Model::Generator.zone
        bad_zone.tags = Set{"bad", "really bad"}
        bad_zone.save!

        mod = Model::Generator.module.save!

        cs = Model::Generator.control_system

        cs.zones = [good_zone.id, bad_zone.id].compact
        cs.modules = [mod.id].compact

        cs.save!

        hierarchy_zones = Mappings.hierarchy_zones(mod.driver.as(Model::Driver))
        hierarchy_zones.size.should eq 1
        hierarchy_zones.first.id.should eq good_zone.id
      end

      it "gets scope zones for Module" do
        Model::Module.clear
        Model::ControlSystem.clear
        Model::Zone.clear
        Model::Driver.clear

        good_zone = Model::Generator.zone
        good_zone.tags = Set{Mappings.scope, "good"}
        good_zone.save!
        bad_zone = Model::Generator.zone
        bad_zone.tags = Set{"bad", "really bad"}
        bad_zone.save!

        mod = Model::Generator.module.save!

        cs = Model::Generator.control_system

        cs.zones = [good_zone.id, bad_zone.id].compact
        cs.modules = [mod.id].compact

        cs.save!

        hierarchy_zones = Mappings.hierarchy_zones(mod)
        hierarchy_zones.size.should eq 1
        hierarchy_zones.first.id.should eq good_zone.id
      end

      it "gets scope zones for top-level Zone" do
        Model::Zone.clear

        zone = Model::Generator.zone
        zone.tags = Set{Mappings.scope}

        hierarchy_zones = Mappings.hierarchy_zones(zone)
        hierarchy_zones.size.should eq 1
        hierarchy_zones.first.id.should eq zone.id
      end

      it "gets scope zones for sub-hierarchy Zone" do
        Model::Zone.clear
        parent_zone = Model::Generator.zone
        parent_zone.tags = Set{Mappings.scope, "good"}
        parent_zone.save!
        child_zone = Model::Generator.zone
        child_zone.tags = Set{HIERARCHY[1], "really bad"}
        child_zone.parent = parent_zone
        child_zone.save!

        hierarchy_zones = Mappings.hierarchy_zones(child_zone)
        hierarchy_zones.size.should eq 1
        hierarchy_zones.first.id.should eq parent_zone.id
      end
    end
  end
end
