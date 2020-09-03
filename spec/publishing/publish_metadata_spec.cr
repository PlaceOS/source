require "../spec_helper"

module PlaceOS::Ingest
  record MockModel, id : String, some_data : String do
    include JSON::Serializable

    def destroyed?
      false
    end
  end

  class MockManager
    include PublisherManager

    getter messages : Array(Publisher::Message) = [] of Publisher::Message

    def broadcast(message)
      messages << message
    end
  end

  class Dummy
    include PublishMetadata(MockModel)
    getter publisher_managers : Array(PlaceOS::Ingest::MockManager) = [PlaceOS::Ingest::MockManager.new]
  end

  describe PublishMetadata do
    it "drops metadata event if model is missing a top-level zone" do
      router = Dummy.new
      zone = Model::Generator.zone
      zone.tags = Set{"not", "top", "level"}
      mock = MockModel.new(id: "hello", some_data: "edkh")
      router.publish_metadata(zone, mock)

      Fiber.yield

      router.publisher_managers.first.messages.should be_empty
    end

    it "publishes metadata event if model has a top-level zone" do
      zone = Model::Generator.zone
      zone.tags = Set{Mappings.scope, "not", "top", "level"}

      payload = {id: "hello", some_data: "edkh"}
      mock = MockModel.new(**payload)

      router = Dummy.new
      router.publish_metadata(zone, mock)

      Fiber.yield

      message = router.publisher_managers.first.messages.first?
      message.should_not be_nil
      message = message.not_nil!
      message.data.should eq Mappings::Metadata.new("hello", "org")
      message.payload.should eq payload.to_json
    end
  end
end
