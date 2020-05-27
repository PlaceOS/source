require "models/control_system"

require "../constants"
require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher"
require "../resource"

module PlaceOS::MQTT::Router
  # System router (If correctly scoped)
  # - Publishes metadata
  # - Listens for changes to the `zones` array
  #   + updates system_zones
  # - Listens for changes to the `modules` array
  #   + updates system_modules
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
      system = event[:resource]

      hierarchy_zones = Mappings.hierarchy_zones(system)
      return Resource::Result::Skipped if hierarchy_zones.empty?

      hierarchy_zones.each do |zone|
        publish_metadata(zone, system)
      end

      case event[:action]
      when Resource::Action::Created
      when Resource::Action::Updated
      when Resource::Action::Deleted
      end

      Resource::Result::Skipped
    end

    def self.system_zone_mapping(zone_id : String, zone_tags : Array(String), mapping : ZoneMapping? = nil, destroyed : Bool = false)
      mapping = {} of String => String if mapping.nil?

      # Remove stale zone tags
      mapping.delete_if? { |tag, id| id == zone_id && (destroyed || !tag.in?(zone_tags)) }

      unless destroyed
        # Update ZoneMapping with new zone tags
        zone_tags.each { |tag| mapping[tag] = zone_id }
      end

      mapping
    end

    def self.create_system_zone_mapping(
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
        system_zone_mapping(zone_id, zone_tags) unless zone_tags.empty?
      end

      # Merge individual zone_mappings into a single ZoneMapping hash
      zone_mappings.reduce({} of String => String) do |acc, mapping|
        acc.merge!(mapping)
      end
    end

    # Map from `module_id` => {control_system_id: String, name: String, index: Int32}
    def self.system_modules(system : Model::System) : Hash(String, Mapping::SystemModule)
      module_ids = system.module
      control_system_id = system.id.as(String)

      return {} of String => Mappings::SystemModule if module_ids.nil? || module_ids.empty?

      # module_name => [module_id]
      # Order module_ids, grouped by resolved name
      grouped = Model::Module
        .find_all(module_ids)
        .each_with_object(Hash(String, Array(String)).new([] of String)) { |mod, mapping|
          mapping[mod.resolved_name.as(String)] << mod.id.as(String)
        }

      # module_id => Mappings::SystemModule
      # Generate SystemModule mappings
      grouped.each_with_object({} of String => Mappings::SystemModule) do |(name, ids), mapping|
        ids.each_with_index(offset: 1) do |id, index|
          mapping[id] = {name: name, control_system_id: control_system_id, index: index}
        end
      end
    end
  end
end
