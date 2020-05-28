require "models/module"

require "../mappings"
require "../resource"

module PlaceOS::MQTT::Router
  # Module router...
  # - Listen for changes to the Module's name and update `system_module_mappings`
  # - Maintain module_id -> driver_id mapping
  class Module < Resource(Model::Module)
    private getter mappings : Mappings
    Log = ::Log.for("mqtt.router.module")

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
        state.drivers.reject!(module_id)
        state.system_modules.delete(module_id)
      end
    end

    def process_resource(event) : Resource::Result
      mod = event[:resource]

      hierarchy_zones = Mappings.hierarchy_zones(mod)
      return Resource::Result::Skipped if hierarchy_zones.empty?

      case event[:action]
      when Resource::Action::Created
        handle_create(mod)
      when Resource::Action::Updated
        handle_update(mod)
      when Resource::Action::Deleted
        handle_delete(mod)
      end.as(Resource::Result)
    end
  end
end
