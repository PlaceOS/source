require "placeos-driver/storage"
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

    # Queue removal of everything this Module currently publishes.
    #
    # Best effort: the statuses come from the Module's storage, which another
    # service may already have cleared by the time a delete reaches us. What is
    # still there gets removed, and anything already gone was never ours to find
    def remove_retained_state(module_id : String) : Nil
      return if publisher_managers.empty?

      statuses = begin
        PlaceOS::Driver::RedisStorage.new(module_id).keys
      rescue error
        Log.debug(exception: error) { "no stored state for Module<#{module_id}>" }
        [] of String
      end
      return if statuses.empty?

      # resolved against the mapping as it stands, so these are the old topics
      events = mappings.current_status_events(module_id, statuses)
      return if events.empty?

      # the payload is discarded — a removal is a zero length retained publish
      timestamp = Time.utc
      events.each do |event|
        message = Publisher::Message.new(event, nil, timestamp)
        publisher_managers.each(&.broadcast_delete(message))
      end

      Log.info { "queued removal of #{events.size} retained value(s) for Module<#{module_id}>" }
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
      #
      # NOTE:: the name is a topic segment, so a rename moves every status this
      # Module publishes. The old topics have to be removed *before* the mapping
      # is rewritten, while they can still be resolved
      if mod.custom_name_changed?
        remove_retained_state(module_id)

        # Update the `system_module` entry for each ControlSystem that has a reference to the Module
        Model::ControlSystem.by_module_id(module_id).each do |cs|
          mappings.set_system_modules(cs.id.as(String), Router::ControlSystem.system_modules(cs))
        end
      end

      Resource::Result::Success
    end

    def handle_delete(mod : Model::Module)
      module_id = mod.id.as(String)

      # again, before the mapping goes, or the topics cannot be resolved
      remove_retained_state(module_id)

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
