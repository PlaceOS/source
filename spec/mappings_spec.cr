require "./spec_helper"

module PlaceOS::MQTT
  describe Mappings do
    describe "state_event_keys?" do
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

        mappings = Mappings.new(state)
        keys = mappings.state_event_keys?("mod-1234", "power")
        keys.should_not be_nil
        keys.not_nil!.first?.should eq "placeos/org-donor/state/cards/nek/2042/cs-9445/12345/M'Odule/1/power"
      end

      it "doesn't create topics for Modules without a top-level scope Zone" do
        state = mock_state(module_id: "mod-1234", control_system_id: "cs-id")

        # Remove the top level scope mapping
        state.system_zones["cs-id"].delete(Mappings.scope)

        mappings = Mappings.new(state)
        keys = mappings.state_event_keys?("mod-1234", "power")
        keys.should_not be_nil
        keys.not_nil!.should be_empty
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

        mappings = Mappings.new(state)
        keys = mappings.state_event_keys?("mod-1234", "power")
        keys.should_not be_nil
        keys.not_nil!.first?.should eq "placeos/org-donor/state/_/nek/2042/cs-9445/12345/M'Odule/1/power"
      end
    end

    describe "hierarchy_zones" do
      it "gets scope zones for ControlSystem" do
        parallel Model::ControlSystem.clear, Model::Zone.clear

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
        parallel Model::Module.clear, Model::ControlSystem.clear, Model::Zone.clear, Model::Driver.clear

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
        parallel Model::Module.clear, Model::ControlSystem.clear, Model::Zone.clear, Model::Driver.clear

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
