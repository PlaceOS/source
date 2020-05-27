require "models/zone"

require "../constants"
require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"
require "../resource"

module PlaceOS::MQTT::Router
  # Zone router (if scoped)...
  # - listens for changes to Zone's tags and update zone_mappings in Mappings
  # - publishes metadata
  #
  # A Zone _SHOULD NOT_ have more than one hierarchical tag
  class Zone < Resource(Model::Zone)
    include PublishMetadata(Model::Zone)
    Log = ::Log.for("mqtt.router.zone")

    private getter mappings : Mappings
    private getter publisher_manager : PublisherManager

    delegate :scope, to: Mappings

    def initialize(@mappings : Mappings, @publisher_manager : PublisherManager = PublisherManager.instance)
      super()
    end

    # Update
    # - update system zone mappings
    # Delete
    # - remove system zone mappings
    #
    # Publish zone if is scope or under scope

    def process_resource(event) : Resource::Result
      zone = event[:resource]

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
    def update_zone_mapping(zone : Model::Zone)
      zone_id = zone.id.as(String)
      # Find tags from hierarchy
      zone_tags = zone.tag_list & HIERARCHY
      # Ignore zone if tags do not fall in the hierarchy
      return Resource::Result::Skipped if zone_tags.empty?

      destroyed = zone.destroyed?

      mappings.write do |state|
        state.zone_mappings.transform_values! do |mapping|
          Mappings.zone_mapping(zone_id, zone_tags, mapping, destroyed)
        end
      end

      Resource::Result::Success
    end
  end
end
