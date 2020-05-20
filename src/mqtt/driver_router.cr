require "models/driver"

require "./publisher_manager"
require "./publish_metadata"
require "./resource"

module PlaceOS::MQTT
  # Driver router...
  # - listens for changes to the Driver, creating / removing DriverMappings
  # - publishes metadata
  class DriverRouter < Resource(Model::Driver)
    include PublishMetadata(Model::Driver)
    private getter publisher_manager : PublisherManager
    private getter system_router : SystemRouter

    # TODO:
    # - Ignore publishing driver metadata when no modules scoped
    # - Retroactively publish metadata if module (driver) is scoped

    delegate :scope, to: SystemRouter

    def initialize(@system_router : SystemRouter, @publisher_manager : PublisherManager = PublisherManager.instance)
      super()
    end

    def process_resource(model) : Resource::Result
      # TODO: Cleanup the driver_id -> module_id mapping on delete (in SystemRouter)
      # TODO: Check driver is in scope before publishing metadata
      publish_metadata(scope, model)
    end
  end
end
