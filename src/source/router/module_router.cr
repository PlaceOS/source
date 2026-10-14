require "placeos-models/module"
require "placeos-resource"

require "../mappings"
require "../publishing/publisher_manager"

module PlaceOS::Source::Router
  # Module router...
  # - Listen for changes to the Module's name and update `system_modules`
  # - Maintain module_id -> driver_id mapping
  class Module < Resource(Model::Module)
    private getter mappings : Mappings
    private getter publisher_managers : Array(PublisherManager)
    Log = ::Log.for(self)

    def initialize(@mappings : Mappings, @publisher_managers : Array(PublisherManager) = [] of PublisherManager)
      super()
    end

    def handle_create(mod : Model::Module)
      mappings.write do |state|
        state.drivers[mod.id.as(String)] = mod.driver_id.as(String)
      end

      Resource::Result::Success
    end

    def handle_update(mod : Model::Module)
      module_id = mod.id.as(String)

      # NOTE:: the name is a topic segment, so a rename moves every status this
      # Module publishes, and can shift the index of others with either name
      if mod.custom_name_changed?
        system_ids = Model::ControlSystem.by_module_id(module_id).map do |cs|
          mappings.set_system_modules(cs.id.as(String), Router::ControlSystem.system_modules(cs))
          cs.id.as(String)
        end
        mappings.reconcile_systems(system_ids)
      end

      Resource::Result::Success
    end

    def handle_delete(mod : Model::Module)
      module_id = mod.id.as(String)

      # the systems it was in, while the mapping still says so
      system_ids = mappings.read do |state|
        state.system_modules[module_id]?.try(&.map(&.[:control_system_id])) || [] of String
      end

      mappings.write do |state|
        # Remove reference in drivers
        state.drivers.delete(module_id)
        state.system_modules.delete(module_id)
      end

      # What it published is known from the registry, not from its storage,
      # which core may already have cleared
      mappings.reconcile({module_id})
      mappings.reconcile_systems(system_ids)

      Resource::Result::Success
    end

    def process_resource(action : Resource::Action, resource : Model::Module) : Resource::Result
      mod = resource

      hierarchy_zones = Mappings.hierarchy_zones(mod)
      return Resource::Result::Skipped if hierarchy_zones.empty? && !action.deleted?

      case action
      in .created?
        handle_create(mod)
      in .updated?
        handle_update(mod)
      in .deleted?
        handle_delete(mod)
      end
    end
  end
end
