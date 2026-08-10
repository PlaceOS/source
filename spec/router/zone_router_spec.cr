require "../spec_helper"

module PlaceOS::Source
  describe Router::Zone do
    it "ignores Zones without a tag in the hierarchy" do
      Model::Zone.clear

      zone = Model::Generator.zone
      zone.tags = Set{"hmm"}
      zone.id = "zone-abcde1232"

      router = Router::Zone.new(Mappings.new, [] of PublisherManager)
      router.@event_channel.send(Resource::Event.new(:created, zone))
      router.start

      router.processed.should be_empty
    end

    # A hierarchy tag decides which level of the topic a Zone occupies, so
    # retagging a Zone moves the topic for every system mapped to it
    it "updates existing system_zones on tag change" do
      Model::Zone.clear

      zone = Model::Generator.zone
      zone.id = "zone-retagged"
      zone.tags = Set{"level"}

      # a system already mapped with this Zone at its original level
      state = Mappings::State.new
      state.system_zones["cs-mapped"] = {"org" => "zone-org", "level" => "zone-retagged"}
      mappings = Mappings.new(state)

      router = Router::Zone.new(mappings, [] of PublisherManager)

      # retagged from level to building
      zone.tags = Set{"building"}
      router.update_zone_mapping(zone)

      mapping = mappings.read { |current| current.system_zones["cs-mapped"] }
      # moved rather than duplicated: the stale level entry has to go
      mapping.should eq({"org" => "zone-org", "building" => "zone-retagged"})
    end

    it "removes a Zone from system_zones when it is destroyed" do
      Model::Zone.clear

      state = Mappings::State.new
      state.system_zones["cs-mapped"] = {"org" => "zone-org"}
      mappings = Mappings.new(state)

      # has to be persisted before it can be destroyed, otherwise `destroyed?`
      # stays false and the router treats it as a plain update
      zone = Model::Generator.zone
      zone.tags = Set{"level"}
      zone.save!

      state.system_zones["cs-mapped"]["level"] = zone.id.as(String)
      zone.destroy
      zone.destroyed?.should be_true

      Router::Zone.new(mappings, [] of PublisherManager).update_zone_mapping(zone)

      mappings.read { |current| current.system_zones["cs-mapped"] }.should eq({"org" => "zone-org"})
    end
  end
end
