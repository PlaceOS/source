require "models/control_system"
require "models/module"
require "models/zone"
require "rwlock"

require "./constants"
require "./publish_metadata"
require "./publisher"
require "./resource"

module PlaceOS::MQTT
  # System router...
  # - listens for changes to the zone_ids list, and updates zone_mappings accordingly
  # - publishes metadata
  class SystemRouter < Resource(Model::ControlSystem)
    include PublishMetadata(Model::ControlSystem)
    Log = ::Log.for("mqtt.system_router")

    class_getter scope : String = HIERARCHY.first? || abort "Hierarchy must contain at least one scope"

    private getter publisher_manager : PublisherManager

    def initialize(@publisher_manager : PublisherManager = PublisherManager.instance)
      super()
    end

    def process_resource(event) : Resource::Result
      Resource::Result::Skipped
    end

    # Handle Updates to existing Zone tags
    #
    def update_zone_mapping(zone : Model::Zone)
      zone_id = zone.id.as(String)
      # Find tags from hierarchy
      zone_tags = zone.tag_list & HIERARCHY
      # Ignore zone if tags do not fall in the hierarchy
      return if zone_tags.empty?

      destroyed = zone.destroyed?

      write_zone_mappings do |zone_mappings|
        zone_mappings.transform_values! do |mapping|
          SystemRouter.zone_mapping(zone_id, zone_tags, mapping, destroyed)
        end
      end
    end

    def self.zone_mapping(zone_id : String, zone_tags : Array(String), mapping : ZoneMapping? = nil, destroyed : Bool = false)
      mapping = {} of String => String if mapping.nil?

      # Remove stale zone tags
      mapping.delete_if? { |tag, id| id == zone_id && (destroyed || !tag.in?(zone_tags)) }

      unless destroyed
        # Update ZoneMapping with new zone tags
        zone_tags.each { |tag| mapping[tag] = zone_id }
      end

      mapping
    end

    def self.create_zone_mapping(
      system : Model::System
    ) : ZoneMapping
      # Look up zones
      zone_list = system.zones

      # TODO: Put this logic into RethinkORM #get_all
      zones = if zone_list.nil? || zone_list.empty?
                [] of Model::Zone
              else
                Model::Zones.get_all(zone_list)
              end

      # Generate zone mappings
      zone_mappings = zones.compact_map do |zone|
        zone_id = zone.id.as(String)
        # Find tags from hierarchy
        zone_tags = zone.tag_list & HIERARCHY
        zone_mapping(zone_id, zone_tags) unless zone_tags.empty?
      end

      # Merge individual zone_mappings into a single ZoneMapping hash
      zone_mappings.reduce({} of String => String) do |acc, mapping|
        acc.merge!(mapping)
      end
    end

    # Construct a Module `state` event key prefix
    #
    # If a ZoneMapping is missing, the corresponding hierarchy value will be '_'
    def self.state_event_prefix(driver_id : String, zone_mapping : ZoneMapping, module_mapping : ModuleMapping) : String?
      module_key = File.join(driver_id, module_mapping[:name], module_mapping[:index])

      # Look up zone or replace with _ if not present
      hierarchy_values = HIERARCHY.map { |key| zone_mapping[key]? || "_" }

      # Get concrete values
      scope_value = hierarchy_values.first?

      # Prevent publishing unspecified top level scope events
      return if scope_value.nil? || scope_value == "_"

      subhierarchy_values = hierarchy_values[1..]

      "/#{scope_value}/state/#{File.join(subhierarchy_values)}/#{module_key}"
    end

    # Mappings access
    # TODO: Factor all this state into an object that is written to by the routes
    #       and read from by the publisher
    ###########################################################################

    @driver_mappings : Hash(String, String) = {} of String => String

    alias ModuleMapping = NamedTuple(system_id: String, name: String, index: String)
    @module_mappings : Hash(String, Array(ModuleMapping)) = Hash(String, Array(ModuleMapping)).new { [] of ModuleMapping }

    alias ZoneMapping = Hash(String, String)
    @zone_mappings : Hash(String, ZoneMapping) = {} of String => ZoneMapping

    private getter driver_mappings_lock : RWLock = RWLock.new
    private getter module_mappings_lock : RWLock = RWLock.new
    private getter zone_mappings_lock : RWLock = RWLock.new

    # Synchronized read access to the driver_mappings hash
    def read_driver_mappings(& : Hash(String, String) ->)
      module_mappings_lock.read do
        yield @driver_mappings
      end
    end

    # Synchronized write access to the driver_mappings hash
    def write_driver_mappings(& : Hash(String, String) ->)
      module_mappings_lock.write do
        yield @driver_mappings
      end
    end

    # Synchronized read access to the module_mappings hash
    def read_module_mappings(& : Hash(String, Array(ModuleMapping)) ->)
      module_mappings_lock.read do
        yield @module_mappings
      end
    end

    # Synchronized write access to the module_mappings hash
    def write_module_mappings(& : Hash(String, Array(ModuleMapping)) ->)
      module_mappings_lock.write do
        yield @module_mappings
      end
    end

    # Synchronized read access to the zone_mappings hash
    def read_zone_mappings(& : Hash(String, ZoneMapping) ->)
      zone_mappings_lock.read do
        yield @zone_mappings
      end
    end

    # Synchronized write access to the zone_mappings hash
    def write_zone_mappings(& : Hash(String, ZoneMapping) ->)
      zone_mappings_lock.write do
        yield @zone_mappings
      end
    end
  end
end
