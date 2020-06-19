require "placeos-models/driver"

require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"
require "../resource"

module PlaceOS::MQTT::Router
  # Driver router...
  # - removes driver mapping if driver removed
  # - publishes metadata (if correctly scoped)
  class Driver < Resource(Model::Driver)
    include PublishMetadata(Model::Driver)
    Log = ::Log.for("mqtt.router.driver")

    private getter mappings : Mappings
    private getter publisher_manager : PublisherManager

    def initialize(@mappings : Mappings, @publisher_manager : PublisherManager = PublisherManager.instance)
      super()
    end

    def process_resource(event) : Resource::Result
      action = event[:action]
      driver = event[:resource]
      driver_id = driver.id.as(String)

      hierarchy_zones = Mappings.hierarchy_zones(driver)
      return Resource::Result::Skipped if hierarchy_zones.empty?

      hierarchy_zones.each do |zone|
        publish_metadata(zone, driver)
      end

      if action == Resource::Action::Deleted
        mappings.write do |state|
          # Remove references to this Driver
          state.drivers.reject! { |_, id| id == driver_id }
        end
      end

      Resource::Result::Error
    end
  end
end
