require "models/control_system"
require "models/module"
require "models/zone"
require "rwlock"

require "./constants"

module PlaceOS::MQTT
  # Consolidated data object maintaining mappings
  #
  # Handles...
  # - topic generation for MQTT
  # - distinguishing whether model metadata should be published
  class Mappings
    Log = ::Log.for("mqtt.mappings")

    class_getter scope : String = HIERARCHY.first? || abort "Hierarchy must contain at least one scope"

    # Status Keys
    ###########################################################################

    # Generates topic keys if event is to be published.
    #
    # Keys are in the format below.
    # `placeos/<scope zone>/state/<2nd zone_id>/../<nth zone_id>/<system_id>/<driver_id>/<module_name>/<index>/<status>`
    def state_event_keys?(module_id : String, status : String) : Array(String)?
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
          zone_mapping = state.zone_mappings[control_system_id]?
          if zone_mapping
            key_data = {
              status:            status,
              index:             system_module_mapping[:index],
              module_name:       system_module_mapping[:name],
              driver_id:         driver_id,
              control_system_id: control_system_id,
              zone_mapping:      zone_mapping,
            }

            key = Mappings.generate_status_key?(**key_data)

            Log.debug { key_data.merge({message: "could not generate key"}) } if key.nil?

            key
          end
        end
      end
    end

    # Construct a Module `state` key
    #
    # If a ZoneMapping is missing, the corresponding hierarchy value will be '_'
    def self.generate_status_key?(
      status : String,
      index : Int32,
      module_name : String,
      driver_id : String,
      control_system_id : String,
      zone_mapping : ZoneMapping
    ) : String?
      # Look up zone or replace with _ if not present
      hierarchy_values = HIERARCHY.map { |key| zone_mapping[key]? || "_" }

      # Get concrete values
      scope_value = hierarchy_values.first?

      # Prevent publishing events with unspecified top-level scope
      return if scope_value.nil? || scope_value == "_"

      subhierarchy_values = hierarchy_values[1..]

      module_key = File.join(control_system_id, driver_id, module_name, index, status)

      "/#{scope_value}/state/#{File.join(subhierarchy_values)}/#{module_key}"
    end

    # Hierarchy and Scoping
    ###########################################################################

    alias Scoped = Model::ControlSystem | Model::Driver | Model::Module | Model::Zone

    # Always check DB when looking up scope.
    #
    # Caches are only for quick lookups when processing events.
    def hierarchy_zones(model : Scoped) : Array(Zone)
      case model
      when Model::ControlSystem
        Model::Zones
          .find_all(model.zones.as(Array(String)))
          .reject { |zone| hierarchy_tag?(zone).nil? }
      when Model::Driver
        Model::Module
          .by_driver_id(model.id.as(String))
          .flat_map { |mod| scope(mod) }
          .uniq
      when Model::Module
        Model::ControlSystem
          .by_module_id(model.id.as(String))
          .flat_map { |cs| scope(cs) }
          .uniq
      when Model::Zone
        zone = model.parent || model
        if hierarchy_tag?(zone) == Mappings.scope
          [zone]
        else
          [] of Zone
        end
      end
    end

    def self.hierarchy_tag?(zone : Model::Zone) : String?
      hierarchy_tags = zone.tag.as(Array(String)) & HIERARCHY
      # TODO: Error if more than one matching hierarchy tag
      hierarchy_tags.first?
    end

    # System Modules
    ###########################################################################

    def merge_system_modules(control_system_id : String, system_modules : Hash(String, SystemModule))
      write_state do |state|
        # Clear mappings of all references to control_system_id
        state.system_modules.transform_values do |mappings|
          mappings.reject! { |sys_mod| sys_mod[:control_system_id] == control_system_id }
        end

        system_modules.each do |mapping|
          mapping.each do |module_id, new_mapping|
            state.system_modules[module_id] << new_mapping
          end
        end
      end
    end

    # Mappings
    ###########################################################################

    alias SystemModule = NamedTuple(name: String, control_system_id: String, index: Int32)

    # Wrapper for Mapping state
    class State
      # module_id => [{control_system_id: String, index: Int32}]
      getter system_modules : Hash(String, Array(SystemModule)) = Hash(String, Array(SystemModule)).new { [] of SystemModule }

      # module_id => driver_id
      getter driver : Hash(String, String) = {} of String => String

      # control_system_id => { hierarchy_tag => zone_id }
      getter system_zones : Hash(String, Hash(String, String)) = {} of String => Hash(String, String)
    end

    @state : State = State.new

    # Synchronized read access to `Mappings`
    def read
      mappings_lock.read do
        yield @state
      end
    end

    # Synchronized write access to `Mappings`
    def write
      mappings_lock.write do
        yield @state
      end
    end
  end
end
