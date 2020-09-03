require "placeos-models/zone"
require "placeos-resource"

require "../constants"
require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"

module PlaceOS::Ingest::Router
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
      return Resource::Result::Skipped if hierarchy_zones.empty?

      hierarchy_zones.each do |parent_zone|
        publish_metadata(parent_zone, zone)
      end

      # Update/destroy Zone mappings
      if zone.tags_changed? || zone.destroyed?
        update_zone_mapping(zone)
      else
        Resource::Result::Success
      end
    end

    # Handle Updates to existing Zone tags
    #
    def update_zone_mapping(zone : PlaceOS::Model::Zone)
      zone_tag = Mappings.hierarchy_tag?(zone)
      # Ignore zone if tags do not fall in the hierarchy
      return Resource::Result::Skipped if zone_tag.nil?

      zone_id = zone.id.as(String)
      destroyed = zone.destroyed?

      mappings.write do |state|
        state.system_zones.transform_values! do |mapping|
          Mappings.zone_mapping(zone_id, zone_tag, mapping, destroyed)
        end
      end

      Resource::Result::Success
    end
  end
end
