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

      pending "gets scope zones for Driver" do
      end
      pending "gets scope zones for Module" do
      end
      pending "gets scope zones for Zone" do
      end
    end
  end
end
