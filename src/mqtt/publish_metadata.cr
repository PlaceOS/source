require "./publisher"

module PlaceOS::MQTT
  module PublishMetadata(Model)
    abstract def publisher : Publisher

    # Publish to the metadata topic
    def publish_metadata(scope : String, model : Model)
      payload = model.destroyed? ? nil : model.to_json
      publisher.send_metadata(scope, model.id.as(String), payload)
    end
  end
end
