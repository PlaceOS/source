require "./publisher"
require "./publisher_manager"

module PlaceOS::MQTT
  module PublishMetadata(Model)
    abstract def publisher_manager : PublisherManager

    # Publish to the metadata topic
    def publish_metadata(scope : String, model : Model)
      payload = model.destroyed? ? nil : model.to_json
      # Fire off broadcast
      spawn { publisher_manager.broadcast(Publisher.metadata(scope, model.id.as(String), payload)) }
    end
  end
end
