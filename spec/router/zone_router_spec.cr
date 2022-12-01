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

    pending "updates existing system_zones on tag change" do
    end
  end
end
