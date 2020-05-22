require "models/module"

require "../mappings"
require "../resource"

module PlaceOS::MQTT::Router
  # Module router...
  # - listens for changes to the Module's name and update `system_module_mappings`
  # - maintain module_id -> driver_id mapping
  # - fire a `Resource::Action::Created` Driver event to Router::Driver if no existing mapping for module
  #   + this ensures the driver's metadata will be published
  class Module < Resource(Model::Module)
    private getter mappings : Mappings
    Log = ::Log.for("mqtt.router.module")

    def initialize(@mappings : Mappings)
      super()
    end

    def process_resource(model) : Resource::Result
      Resource::Result::Skipped
    end
  end
end
