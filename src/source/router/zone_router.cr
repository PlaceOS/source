require "placeos-models/zone"
require "placeos-resource"

require "../constants"
require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"
require "./control_system_router"

module PlaceOS::Source::Router
  # Zone router (if scoped)...
  # - listens for changes to Zone's tags and update system_zones in Mappings
  # - publishes metadata
  # Note: SystemRouter handles creation of system_zones
  #
  # A Zone _SHOULD NOT_ have more than one hierarchical tag
  class Zone < Resource(PlaceOS::Model::Zone)
    include PublishMetadata(PlaceOS::Model::Zone)
    Log = ::Log.for(self)

    private getter mappings : Mappings
    private getter publisher_managers : Array(PublisherManager)

    def initialize(@mappings : Mappings, @publisher_managers : Array(PublisherManager))
      super()
    end

    # Update
    # - update system zone mappings
    # Delete
    # - remove system zone mappings
    #
    # Publish zone if is scope or under scope
    def process_resource(action : Resource::Action, resource : PlaceOS::Model::Zone) : Resource::Result
      zone = resource

      hierarchy_zones = Mappings.hierarchy_zones(zone)
      return Resource::Result::Skipped if hierarchy_zones.empty? && !action.deleted?

      publish_metadata(hierarchy_zones, zone)

      # Update/destroy Zone mappings
      if zone.tags_changed? || zone.destroyed?
        update_zone_mapping(zone)
      else
        Resource::Result::Success
      end
    end

    # Handle a change to a Zone's tags, or its removal.
    #
    # Only systems that have the zone are touched. Every system's mapping used
    # to be passed through `Mappings.zone_mapping`, which adds the zone to any
    # mapping that does not have it yet — so retagging one zone put it in the
    # hierarchy of every system, and moved all of their topics.
    #
    # Mappings that have the zone are patched; then every system the database
    # says is in the zone is rebuilt from it, which also covers a zone that has
    # just gained or lost its hierarchy tag
    def update_zone_mapping(zone : PlaceOS::Model::Zone)
      zone_id = zone.id.as(String)
      zone_tag = Mappings.hierarchy_tag?(zone)
      remove = zone.destroyed? || zone_tag.nil?

      mapped = mappings.systems_in_zone(zone_id)
      mappings.write do |state|
        mapped.each do |control_system_id|
          next unless mapping = state.system_zones[control_system_id]?
          if remove
            mapping.reject! { |_, id| id == zone_id }
          else
            Mappings.zone_mapping(zone_id, zone_tag.as(String), mapping)
          end
        end
      end

      in_zone = remove ? [] of PlaceOS::Model::ControlSystem : PlaceOS::Model::ControlSystem.by_zone_id(zone_id).to_a
      rebuilt = in_zone.map { |cs| {cs.id.as(String), Router::ControlSystem.system_zones(cs)} }
      mappings.write do |state|
        rebuilt.each { |(control_system_id, mapping)| state.system_zones[control_system_id] = mapping }
      end

      # the zone is a topic segment of every status in those systems
      mappings.reconcile_systems(mapped | rebuilt.map(&.[0]).to_set)

      Resource::Result::Success
    end
  end
end
