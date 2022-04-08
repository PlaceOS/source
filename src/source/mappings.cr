require "placeos-models"
require "rwlock"

require "./constants"

module PlaceOS::Source
  # Consolidated data object maintaining mappings
  #
  # Handles...
  # - topic generation for MQTT
  # - distinguishing whether model metadata should be published
  class Mappings
    Log = ::Log.for(self)

    class_getter scope : String = HIERARCHY.first? || abort "Hierarchy must contain at least one scope"
    class_getter hierarchy : Array(String) = HIERARCHY
    private class_getter hierarchy_set : Set(String) = HIERARCHY.to_set

    def initialize(@state : State = State.new)
    end

    # State Keys
    ###########################################################################

    # Generates metadata for Status events topic keys if the event is to be published.
    #
    def status_events?(module_id : String, status : String) : Array(Status)?
      read do |state|
        # Check if module is in any relevant ControlSystems
        system_modules = state.system_modules[module_id]?
        if system_modules.nil?
          Log.debug { "no mapped systems for Module<#{module_id}>" }
          return
        end

        # Look up module's driver_id
        driver_id = state.drivers[module_id]?
        if driver_id.nil?
          Log.warn { "missing driver_id for Module<#{module_id}>" }
          return
        end

        system_modules.compact_map do |system_mapping|
          control_system_id = system_mapping[:control_system_id]
          # Lookup hierarchical Zones for the system
          zone_mapping = state.system_zones[control_system_id]?
          if zone_mapping
            Status.new(
              status: status,
              index: system_mapping[:index],
              module_name: system_mapping[:name],
              module_id: module_id,
              driver_id: driver_id,
              control_system_id: control_system_id,
              zone_mapping: zone_mapping,
            )
          end
        end
      end
    end

    record Status,
      status : String,
      index : Int32,
      module_name : String,
      module_id : String,
      driver_id : String,
      control_system_id : String,
      zone_mapping : Hash(String, String)

    record Metadata, model_id : String, scope : String = Mappings.scope

    alias Data = Status | Metadata

    # Hierarchy and Scoping
    ###########################################################################

    alias Scoped = Model::ControlSystem | Model::Driver | Model::Module | Model::Zone

    # Always check DB when looking up scope.
    #
    # Caches are only for quick lookups when processing events.
    def self.hierarchy_zones(model : Scoped) : Array(Model::Zone)
      case model
      in Model::ControlSystem
        Model::Zone
          .find_all(model.zones)
          .reject { |zone| hierarchy_tag?(zone).nil? }
          .to_a
      in Model::Driver
        Model::Module
          .by_driver_id(model.id.as(String))
          .flat_map { |mod| hierarchy_zones(mod) }
          .uniq # ameba:disable Performance/ChainedCallWithNoBang
          .to_a
      in Model::Module
        Model::ControlSystem
          .by_module_id(model.id.as(String))
          .flat_map { |cs| hierarchy_zones(cs) }
          .uniq # ameba:disable Performance/ChainedCallWithNoBang
          .to_a
      in Model::Zone
        zone = model.parent || model
        if hierarchy_tag?(zone) == Mappings.scope
          [zone]
        else
          [] of Model::Zone
        end
      end
    end

    # Calculate the hiearchy tag for a Zone
    #
    def self.hierarchy_tag?(zone : Model::Zone) : String?
      hierarchy_tags = zone.tags & hierarchy_set

      if hierarchy_tags.size > 1
        Log.error { "Zone<#{zone.id}> has more than one hierarchy tag: #{hierarchy_tags}" }
      end

      hierarchy_tags.first?
    end

    # System Zones
    ###########################################################################

    # Update tags for a Zone
    # Set `mapping` to update existing mappings
    def self.zone_mapping(zone_id : String, zone_tag : String, mapping : Hash(String, String)? = nil, destroyed : Bool = false)
      mapping = {} of String => String if mapping.nil?

      # Remove stale zone tags
      existing_tag = mapping.key_for?(zone_id)
      unless existing_tag.nil?
        mapping.delete(existing_tag) if destroyed || existing_tag != zone_tag
      end

      # Update zone mapping with new zone tags
      mapping[zone_tag] = zone_id unless destroyed

      mapping
    end

    # System Modules
    ###########################################################################

    # Update System Module mappings
    def set_system_modules(control_system_id : String, system_modules : Hash(String, SystemModule))
      write do |state|
        # Clear mappings of all references to control_system_id
        remove_system_modules(control_system_id)

        system_modules.each do |module_id, new_mapping|
          state.system_modules[module_id] << new_mapping
        end
      end
    end

    # Remove System Module Mappings
    def remove_system_modules(control_system_id : String)
      # Clear mappings of all references to control_system_id
      write do |state|
        state.system_modules.transform_values! do |mappings|
          mappings.reject! { |sys_mod| sys_mod[:control_system_id] == control_system_id }
        end
      end
    end

    # Mappings
    ###########################################################################

    alias SystemModule = NamedTuple(name: String, control_system_id: String, index: Int32)

    # Wrapper for Mapping state
    class State
      include JSON::Serializable

      # module_id => [{control_system_id: String, index: Int32}]
      getter system_modules : Hash(String, Array(SystemModule)) = Hash(String, Array(SystemModule)).new { |h, k| h[k] = [] of SystemModule }

      # module_id => driver_id
      getter drivers : Hash(String, String) = {} of String => String

      # control_system_id => { hierarchy_tag => zone_id }
      getter system_zones : Hash(String, Hash(String, String)) = {} of String => Hash(String, String)

      def initialize
      end
    end

    private getter mappings_lock : RWLock = RWLock.new

    # Synchronized read access to `Mappings`
    def read
      mappings_lock.read do
        yield @state
      end
    end

    # Synchronized write access to `Mappings`
    def write
      mappings_lock.write do
        v = yield @state
        Log.trace { {
          message:  "wrote mappings",
          mappings: @state.to_json,
        } }
        v
      end
    end
  end
end
