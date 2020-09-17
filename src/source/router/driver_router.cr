require "placeos-models/driver"
require "placeos-resource"

require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"

module PlaceOS::Source::Router
  # Driver router...
  # - removes driver mapping if driver removed
  # - publishes metadata (if correctly scoped)
  class Driver < Resource(PlaceOS::Model::Driver)
    include PublishMetadata(PlaceOS::Model::Driver)
    Log = ::Log.for(self)

    private getter mappings : Mappings
    private getter publisher_managers : Array(PublisherManager)

    def initialize(@mappings : Mappings, @publisher_managers : Array(PublisherManager))
      super()
    end

    def process_resource(action : Resource::Action, resource : PlaceOS::Model::Driver) : Resource::Result
      driver = resource
      driver_id = driver.id.as(String)

      hierarchy_zones = Mappings.hierarchy_zones(driver)

      return Resource::Result::Skipped if hierarchy_zones.empty? && !action.deleted?

      hierarchy_zones.each do |zone|
        publish_metadata(zone, driver)
      end

      if action.deleted?
        mappings.write do |state|
          # Remove references to this Driver
          state.drivers.reject! { |_, id| id == driver_id }
        end
      end

      Resource::Result::Error
    end
  end
end
