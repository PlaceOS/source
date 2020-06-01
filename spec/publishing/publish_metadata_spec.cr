require "../spec_helper"

module PlaceOS::MQTT
  record MockModel, id : String, some_data : String do
    include JSON::Serializable

    def destroyed?
      false
    end
  end

  class MockManager < PublisherManager
    getter messages : Array(Publisher::Metadata | Publisher::State) = [] of Publisher::Metadata | Publisher::State

    def broadcast(message)
      messages << message
    end
  end

  class Dummy
    include PublishMetadata(MockModel)
    getter publisher_manager : MockManager = MockManager.new
  end

  describe PublishMetadata do
    it "drops metadata event if model is missing a top-level zone" do
      router = Dummy.new
      zone = Model::Generator.zone
      zone.tags = Set{"not", "top", "level"}
      mock = MockModel.new(id: "hello", some_data: "edkh")
      router.publish_metadata(zone, mock)

      Fiber.yield

      router.publisher_manager.messages.should be_empty
    end

    it "publishes metadata event if model has a top-level zone" do
      zone = Model::Generator.zone
      zone.tags = Set{Mappings.scope, "not", "top", "level"}
      mock = MockModel.new(id: "hello", some_data: "edkh")

      router = Dummy.new
      router.publish_metadata(zone, mock)

      expected_message = Publisher.metadata(scope: Mappings.scope, id: mock.id, payload: mock.to_json)

      Fiber.yield

      message = router.publisher_manager.messages.first?
      message.should_not be_nil
      message = message.not_nil!

      message.key.should eq expected_message.key
      message.payload.should eq expected_message.payload
    end
  end
end
