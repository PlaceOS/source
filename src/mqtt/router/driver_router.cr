require "models/driver"

require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"
require "../resource"

module PlaceOS::MQTT::Router
  # Driver router...
  # - listens for changes to the Driver, creating / removing DriverMappings
  # - publishes metadata (if correctly scoped)
  class Driver < Resource(Model::Driver)
    include PublishMetadata(Model::Driver)
    Log = ::Log.for("mqtt.router.driver")

    private getter mappings : Mappings
    private getter publisher_manager : PublisherManager

    # TODO:
    # - Ignore publishing driver metadata when no modules scoped
    # - Retroactively publish metadata if module (driver) is scoped

    delegate :scope, to: Mappings

    def initialize(@mappings : Mappings, @publisher_manager : PublisherManager = PublisherManager.instance)
      super()
    end

    def process_resource(model) : Resource::Result
      # TODO: Cleanup the driver_id -> module_id mapping on delete (in SystemRouter)
      # TODO: Check driver is in scope before publishing metadata
      # publish_metadata(scope, model)
      Resource::Result::Error
    end
  end
end
