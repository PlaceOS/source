require "placeos-models/zone"

require "./publisher"
require "./publisher_manager"
require "../mappings"

module PlaceOS::Source
  module PublishMetadata(Model)
    abstract def publisher_managers : Array(PublisherManager)

    # Publish model metadata if any of `zones` is top-level.
    #
    # Once, however many of them are: the topic is the scope, not the zone
    def publish_metadata(zones : Enumerable(::PlaceOS::Model::Zone), model : Model)
      publish_metadata(model) if zones.any? { |zone| Mappings.hierarchy_tag?(zone) == Mappings.scope }
    end

    # Publish model metadata
    #
    # Only models in the top-level hiearchy are published
    def publish_metadata(zone : ::PlaceOS::Model::Zone, model : Model)
      publish_metadata({zone}, model)
    end

    # Publish model metadata, for a model known to be in the top-level hierarchy
    #
    # NOTE:: broadcast here rather than from a fiber of its own. The publisher
    # queues are bounded, and as the routers load, every system and zone is
    # published at once: a fiber each held every one of those models' JSON in
    # memory while it waited its turn. Waiting here holds one
    def publish_metadata(model : Model)
      message = Publisher::Message.new(
        data: Mappings::Metadata.new(model.id.as(String)),
        payload: model.destroyed? ? nil : model.to_json,
        timestamp: Time.utc
      )
      publisher_managers.each &.broadcast(message)
    rescue error
      Log.warn(exception: error) { "publishing metadata for #{model.id}" }
    end
  end
end
