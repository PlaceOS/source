require "models/control_system"
require "models/zone"

require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"
require "../resource"

module PlaceOS::MQTT::Router
  # System router (If correctly scoped)
  # - Publishes metadata
  # - Listens for changes to the `zones` array
  #   + maintain system_zones
  # - Listens for changes to the `modules` array
  #   + maintain system_modules
  # - Remove references to ControlSystem on destroy
  class ControlSystem < Resource(PlaceOS::Model::ControlSystem)
    include PublishMetadata(PlaceOS::Model::ControlSystem)
    Log = ::Log.for("mqtt.router.control_system")

    private getter mappings : Mappings
    private getter publisher_manager : PublisherManager

    delegate :scope, to: Mappings

    def initialize(@mappings : Mappings, @publisher_manager : PublisherManager = PublisherManager.instance)
      super()
    end

    # - Create a system_zones mapping
    # - Create a system_modules mapping
    def handle_create(control_system : PlaceOS::Model::ControlSystem) : Resource::Result
      zone_mappings(control_system)
      module_mappings(control_system)

      Resource::Result::Success
    end

    # - Create a system_zones mapping if zones have changed
    # - Update system_modules mapping if modules have changed
    def handle_update(control_system : PlaceOS::Model::ControlSystem) : Resource::Result
      zone_mappings(control_system) if control_system.zones_changed?
      module_mappings(control_system) if control_system.modules_changed?

      Resource::Result::Success
    end

    # - Remove system_modules references to ControlSystem
    # - Remove system_zones for ControlSystem
    def handle_delete(control_system : PlaceOS::Model::ControlSystem) : Resource::Result
      control_system_id = control_system.id.as(String)

      mappings.write do |state|
        state.system_zones.delete(control_system_id)
      end

      mappings.remove_system_modules(control_system_id)

      Resource::Result::Success
    end

    def process_resource(event) : Resource::Result
      control_system = event[:resource]

      hierarchy_zones = Mappings.hierarchy_zones(control_system)
      return Resource::Result::Skipped if hierarchy_zones.empty?

      hierarchy_zones.each do |zone|
        publish_metadata(zone, control_system)
      end

      case event[:action]
      when Resource::Action::Created
        handle_create(control_system)
      when Resource::Action::Updated
        handle_update(control_system)
      when Resource::Action::Deleted
        handle_delete(control_system)
      end.as(Resource::Result)
    end

    # Create/update a mapping for ControlSystem's Zones
    def zone_mappings(control_system : PlaceOS::Model::ControlSystem)
      system_zone_mappings = Router::ControlSystem.system_zones(control_system)

      mappings.write do |state|
        state.system_zones[control_system.id.as(String)] = system_zone_mappings
      end

      system_zone_mappings
    end

    # Create/update mappings for ControlSystem's Modules
    def module_mappings(control_system : PlaceOS::Model::ControlSystem)
      system_module_mappings = Router::ControlSystem.system_modules(control_system)

      mappings.set_system_modules(control_system.id.as(String), system_module_mappings)

      system_module_mappings
    end

    def self.system_zones(control_system : PlaceOS::Model::ControlSystem) : Hash(String, String)
      # Look up zones
      zone_list = control_system.zones
      return {} of String => String if zone_list.nil? || zone_list.empty?

      # Generate zone mappings
      zone_mappings = PlaceOS::Model::Zone.get_all(zone_list).compact_map do |zone|
        tag = Mappings.hierarchy_tag?(zone)
        Mappings.zone_mapping(zone.id.as(String), tag) unless tag.nil?
      end

      # Merge individual zone_mappings into a single zone mapping hash
      zone_mappings.reduce({} of String => String) do |acc, mapping|
        acc.merge!(mapping)
      end
    end

    # Map from `module_id` => {control_system_id: String, name: String, index: Int32}
    def self.system_modules(control_system : PlaceOS::Model::ControlSystem) : Hash(String, Mappings::SystemModule)
      module_ids = control_system.modules
      control_system_id = control_system.id.as(String)

      return {} of String => Mappings::SystemModule if module_ids.nil? || module_ids.empty?

      # module_name => [module_id]
      # Order module_ids, grouped by resolved name
      grouped = PlaceOS::Model::Module
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
