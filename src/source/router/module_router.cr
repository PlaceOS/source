require "placeos-models/module"
require "placeos-resource"

require "../mappings"

module PlaceOS::Source::Router
  # Module router...
  # - Listen for changes to the Module's name and update `system_modules`
  # - Maintain module_id -> driver_id mapping
  class Module < Resource(Model::Module)
    private getter mappings : Mappings
    Log = ::Log.for(self)

    def initialize(@mappings : Mappings)
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

      # Update all `system_mappings` if Module's `custom_name` changed.
      if mod.custom_name_changed?
        # Update the `system_module` entry for each ControlSystem that has a reference to the Module
        Model::ControlSystem.by_module_id(module_id).each do |cs|
          mappings.set_system_modules(cs.id.as(String), Router::ControlSystem.system_modules(cs))
        end
      end

      Resource::Result::Success
    end

    def handle_delete(mod : Model::Module)
      module_id = mod.id.as(String)
      mappings.write do |state|
        # Remove reference in drivers
        state.drivers.delete(module_id)
        state.system_modules.delete(module_id)
      end

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
