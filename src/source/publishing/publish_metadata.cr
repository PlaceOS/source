require "placeos-models/zone"

require "./publisher"
require "./publisher_manager"
require "../mappings"

module PlaceOS::Source
  module PublishMetadata(Model)
    abstract def publisher_managers : Array(PublisherManager)

    # Publish model metadata
    #
    # Only models in the top-level hiearchy are published
    def publish_metadata(zone : ::PlaceOS::Model::Zone, model : Model)
      if Mappings.hierarchy_tag?(zone) == Mappings.scope
        message = Publisher::Message.new(
          data: Mappings::Metadata.new(model.id.as(String)),
          payload: model.destroyed? ? nil : model.to_json,
        )

        # Fire off broadcast
        spawn { publisher_managers.each &.broadcast(message) }
      end
    end
  end
end
