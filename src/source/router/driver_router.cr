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

      if action.created? && !startup_finished?
        # loading: only its metadata is published, and only if it is in scope
        return Resource::Result::Skipped unless loaded_in_scope.includes?(driver_id)
        publish_metadata(driver)
        return Resource::Result::Success
      end

      hierarchy_zones = Mappings.hierarchy_zones(driver)

      return Resource::Result::Skipped if hierarchy_zones.empty? && !action.deleted?

      publish_metadata(hierarchy_zones, driver)

      if action.deleted?
        # driver_id is a topic segment, so everything published by a Module of
        # this Driver is now at a dead topic
        module_ids = mappings.read do |state|
          state.drivers.compact_map { |mod_id, id| mod_id if id == driver_id }
        end

        mappings.write do |state|
          # Remove references to this Driver
          state.drivers.reject! { |_, id| id == driver_id }
        end
        mappings.reconcile(module_ids)
      end

      Resource::Result::Success
    end

    def start(timeout : Time::Span = LOAD_TIMEOUT) : self
      @loaded_in_scope = nil
      super
    end

    @loaded_in_scope : Set(String)? = nil
    private getter loaded_in_scope_lock = Mutex.new

    # Publishes the metadata of every Driver in scope again
    def republish_metadata : Int32
      scoped = drivers_in_scope
      count = 0
      Mappings.each_model(PlaceOS::Model::Driver) do |driver|
        next unless scoped.includes?(driver.id.as(String))
        publish_metadata(driver)
        count += 1
      end
      count
    end

    # The Drivers with a Module in a system under a top-level zone, from the
    # mappings, which hold every system and Module by the time Drivers load.
    #
    # Worked out once, for loading. Asking the database meant reading every
    # Module of each Driver, then each Module's systems and their zones
    private def loaded_in_scope : Set(String)
      loaded_in_scope_lock.synchronize do
        @loaded_in_scope ||= drivers_in_scope
      end
    end

    # Drivers with a Module in a system under a top-level zone
    private def drivers_in_scope : Set(String)
      mappings.read do |state|
        state.drivers.each_with_object(Set(String).new) do |(module_id, driver_id), found|
          next if found.includes?(driver_id)
          scoped = state.system_modules[module_id]?.try &.any? do |mapping|
            state.system_zones[mapping[:control_system_id]]?.try(&.has_key?(Mappings.scope))
          end
          found << driver_id if scoped
        end
      end
    end
  end
end
