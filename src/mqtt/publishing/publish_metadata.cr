require "placeos-models/zone"

require "./publisher"
require "./publisher_manager"
require "../mappings"

module PlaceOS::MQTT
  module PublishMetadata(Model)
    abstract def publisher_manager : PublisherManager

    # Publish to the metadata topic
    def publish_metadata(zone : ::PlaceOS::Model::Zone, model : Model)
      if Mappings.hierarchy_tag?(zone) == Mappings.scope
        payload = model.destroyed? ? nil : model.to_json
        # Fire off broadcast
        spawn { publisher_manager.broadcast(Publisher.metadata(Mappings.scope, model.id.as(String), payload)) }
      end
    end
  end
end
