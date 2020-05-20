require "models/zone"

require "./publisher_manager"
require "./publish_metadata"
require "./resource"

module PlaceOS::MQTT
  # Zone router...
  # - listens for changes to Zone's tags and update mappings in SystemRouter
  # - publishes metadata
  class ZoneRouter < Resource(Model::Zone)
    include PublishMetadata(Model::Zone)

    private getter publisher_manager : PublisherManager
    private getter system_router : SystemRouter

    delegate :scope, to: system_router

    def initialize(@system_router : SystemRouter, @publisher_manager : PublisherManager = PublisherManager.instance)
      super()
    end

    def process_resource(model) : Resource::Result
      Resource::Result::Skipped
    end
  end
end
