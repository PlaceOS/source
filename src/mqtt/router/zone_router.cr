require "models/zone"

require "../constants"
require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"
require "../resource"

module PlaceOS::MQTT::Router
  # Zone router...
  # - listens for changes to Zone's tags and update zone_mappings in Mappings
  # - publishes metadata (if correctly scoped)
  class Zone < Resource(Model::Zone)
    include PublishMetadata(Model::Zone)
    Log = ::Log.for("mqtt.router.zone")

    private getter mappings : Mappings
    private getter publisher_manager : PublisherManager

    delegate :scope, to: Mappings

    def initialize(@mappings : Mappings, @publisher_manager : PublisherManager = PublisherManager.instance)
      super()
    end

    # If it's a zone Create, cache tags
    # If it's an Update, cache tags + check if the mappings needs to be update
    # Publish zone if is scope or under scope

    def process_resource(event) : Resource::Result
      zone = event[:resource]

      case event[:action]
      when Resource::Action::Created
      when Resource::Action::Updated
      when Resource::Action::Deleted
      end

      # Update/create zone mappings
      if zone.tags_changed? || zone.destroyed?
        # TODO
      end

      Resource::Result::Error
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

      mappings.write_zone_mappings do |zone_mappings|
        zone_mappings.transform_values! do |mapping|
          Mappings.zone_mapping(zone_id, zone_tags, mapping, destroyed)
        end
      end
    end

    def self.should_publish?(zone : Model::Zone)
      # Check if the zone is a scope or under a scope
      parent_id = model.parent_id
      if parent_id.nil?
        if model.tags.try &.includes?(scope)
          # Zone is a scope
          publish_metadata(model.id.as(String), model)
        else
        end
      else
        mappings.zone_tags[model.parent]
        model.parent.tags.try &.includes?(scope)
      end
    end

    def self.scope(zone : Model::Zone) : String?
    end
  end
end
