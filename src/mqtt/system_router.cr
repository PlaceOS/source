require "models/control_system"
require "models/module"
require "models/zone"
require "rwlock"

require "./publish_metadata"
require "./publisher"
require "./resource"

module PlaceOS::MQTT
  # System router...
  # - listens for changes to the zone_ids list, and updates mappings accordingly
  # - publishes metadata
  class SystemRouter < Resource(Model::ControlSystem)
    include PublishMetadata(Model::ControlSystem)
    Log = ::Log.for("mqtt.system_router")

    private getter publisher_manager : PublisherManager

    alias ZoneMapping = Hash(String, String)
    @mappings : Hash(String, ZoneMapping) = {} of String => ZoneMapping

    private getter mappings_lock : RWLock = RWLock.new

    # Synchronized read access to the mappings hash
    def read_mappings(& : Hash(String, ZoneMapping) ->)
      mappings_lock.read do
        yield @mappings
      end
    end

    # Synchronized write access to the mappings hash
    def write_mappings(& : Hash(String, ZoneMapping) ->)
      mappings_lock.write do
        yield @mappings
      end
    end

    DEFAULT_HIERARCHY = ["org", "building", "level", "area"]
    getter hierarchy : Array(String)

    def initialize(@publisher_manager : PublisherManager = PublisherManager.instance, @hierarchy : String = DEFAULT_HIERARCHY)
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
      zone_tags = zone.tag_list & hierarchy
      # Ignore zone if tags do not fall in the hierarchy
      return if zone_tags.empty?

      write_mappings do |mappings|
        mappings.transform_values! do |mapping|
          SystemRouter.zone_mapping(zone_id, zone_tags, mapping)
        end
      end
    end

    def self.zone_mapping(zone_id : String, zone_tags : Array(String), mapping : ZoneMapping? = nil)
      mapping = {} of String => String if mapping.nil?

      # Remove stale zone tags
      mapping.delete_if? { |tag, id| id == zone_id && !tag.in?(zone_tags) }
      # Update ZoneMapping with new zone tags
      zone_tags.each { |tag| mapping[tag] = zone_id }

      mapping
    end

    def self.create_zone_mapping(
      system : Model::System,
      hierarchy : Array(String) = DEFAULT_HIERARCHY
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
      mappings = zones.compact_map do |zone|
        zone_id = zone.id.as(String)
        # Find tags from hierarchy
        zone_tags = zone.tag_list & hierarchy
        zone_mapping(zone_id, zone_tags) unless zone_tags.empty?
      end

      # Merge individual mappings into a single ZoneMapping hash
      mappings.reduce({} of String => String) do |acc, mapping|
        acc.merge!(mapping)
      end
    end

    # Construct a hierarchy prefix.
    #
    # If a mapping is missing, the hierarchy value is '_'
    def self.generate_hierarchy_prefix(system_id : String, mappings : Hash(String, ZoneMapping), hierarchy : Array(String)) : String?
      if zone_mapping = mappings[system_id]?
        # Look up zone or replace with _ if not present
        hierarchy_values = hierarchy.map { |key| zone_mapping[key]? || "_" }
        # Generate prefix
        hierarchy_values.join('/')
      end
    end
  end
end
