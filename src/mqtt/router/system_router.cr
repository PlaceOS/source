require "models/control_system"

require "../constants"
require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher"
require "../resource"

module PlaceOS::MQTT::Router
  # System router...
  # - Listens for changes to the zone_ids list, and updates...
  #   + system zone_mappings
  #   + system_module_mappings
  # - Publishes metadata (if correctly scoped)
  class ControlSystem < Resource(Model::ControlSystem)
    include PublishMetadata(Model::ControlSystem)
    Log = ::Log.for("mqtt.router.control_system")

    private getter mappings : Mappings
    private getter publisher_manager : PublisherManager

    delegate :scope, to: Mappings

    def initialize(@mappings : Mappings, @publisher_manager : PublisherManager = PublisherManager.instance)
      super()
    end

    def process_resource(event) : Resource::Result
      Resource::Result::Skipped
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
    ) : Hash(String, String)
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
  end
end
