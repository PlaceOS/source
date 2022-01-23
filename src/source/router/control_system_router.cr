require "placeos-models/control_system"
require "placeos-models/zone"
require "placeos-resource"

require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"

module PlaceOS::Source::Router
  # ControlSystem router (If correctly scoped)
  # - Publishes metadata
  # - Listens for changes to the `zones` array
  #   + maintain system_zones
  # - Listens for changes to the `modules` array
  #   + maintain system_modules
  # - Remove references to ControlSystem on destroy
  class ControlSystem < Resource(PlaceOS::Model::ControlSystem)
    include PublishMetadata(PlaceOS::Model::ControlSystem)
    Log = ::Log.for(self)

    private getter mappings : Mappings
    private getter publisher_managers : Array(PublisherManager)

    def initialize(@mappings : Mappings, @publisher_managers : Array(PublisherManager))
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

    def process_resource(action : Resource::Action, resource : PlaceOS::Model::ControlSystem) : Resource::Result
      control_system = resource

      hierarchy_zones = Mappings.hierarchy_zones(control_system)

      return Resource::Result::Skipped if hierarchy_zones.empty? && !action.deleted?

      hierarchy_zones.each { |zone| publish_metadata(zone, control_system) }

      case action
      in .created?
        handle_create(control_system)
      in .updated?
        handle_update(control_system)
      in .deleted?
        handle_delete(control_system)
      end
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

    def self.system_zones(control_system : PlaceOS::Model::ControlSystem, zones : Array(PlaceOS::Model::Zone)? = nil) : Hash(String, String)
      # Generate zone mappings
      # NOTE: Duplication decessary due to compiler bug with iteration
      zone_mappings = if !zones.nil?
                        zones.compact_map do |zone|
                          tag = Mappings.hierarchy_tag?(zone)
                          Mappings.zone_mapping(zone.id.as(String), tag) unless tag.nil?
                        end
                      else
                        _system_zones(control_system).compact_map do |zone|
                          tag = Mappings.hierarchy_tag?(zone)
                          Mappings.zone_mapping(zone.id.as(String), tag) unless tag.nil?
                        end
                      end

      # Merge individual zone_mappings into a single zone mapping hash
      zone_mappings.reduce({} of String => String) do |acc, mapping|
        acc.merge!(mapping)
      end
    end

    # Map from `module_id` => {control_system_id: String, name: String, index: Int32}
    def self.system_modules(control_system : PlaceOS::Model::ControlSystem, modules : Array(PlaceOS::Model::Module)? = nil) : Hash(String, Mappings::SystemModule)
      control_system_id = control_system.id.as(String)

      # module_name => [module_id]
      # Order module_ids, grouped by resolved name
      # NOTE: Duplication decessary due to compiler bug with iteration
      grouped = if !modules.nil?
                  modules.each_with_object(Hash(String, Array(String)).new { |h, k| h[k] = [] of String }) { |mod, mapping|
                    mapping[mod.resolved_name] << mod.id.as(String)
                  }
                else
                  _system_modules(control_system).each_with_object(Hash(String, Array(String)).new { |h, k| h[k] = [] of String }) { |mod, mapping|
                    mapping[mod.resolved_name] << mod.id.as(String)
                  }
                end

      # module_id => Mappings::SystemModule
      # Generate SystemModule mappings
      grouped.each_with_object({} of String => Mappings::SystemModule) do |(name, ids), mapping|
        ids.each_with_index(offset: 1) do |id, index|
          mapping[id] = {name: name, control_system_id: control_system_id, index: index}
        end
      end
    end

    # Get zones
    protected def self._system_zones(control_system : PlaceOS::Model::ControlSystem)
      zone_list = control_system.zones || [] of String
      PlaceOS::Model::Zone.find_all(zone_list)
    end

    # Get modules
    protected def self._system_modules(control_system : PlaceOS::Model::ControlSystem)
      module_ids = control_system.modules || [] of String
      PlaceOS::Model::Module.find_all(module_ids)
    end
  end
end
