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

    # Generates topic keys if event is to be published.
    #
    # Keys are in the format below.
    # `placeos/<scope zone>/state/<2nd zone_id>/../<nth zone_id>/<system_id>/<driver_id>/<module_name>/<index>/<status>`
    def state_event_keys?(module_id : String, status : String) : Array(String)?
      read do |state|
        # Check if module is in any relevant ControlSystems
        module_system_mappings = state.module_systems[module_id]?
        if module_system_mappings.nil?
          Log.debug { "no mapped systems for Module<#{module_id}>" }
          return
        end

        # Look up module's driver_id
        driver_id = state.drivers[module_id]?
        if driver_id.nil?
          Log.warn { "missing driver_id for Module<#{module_id}>" }
          return
        end

        # Look up module's name
        module_name = state.module_names[module_id]?
        if module_name.nil?
          Log.warn { "missing name for Module<#{module_id}>" }
          return
        end

        module_system_mappings.compact_map do |system_mapping|
          control_system_id = system_mapping[:control_system_id]
          # Lookup hierarchical Zones for the system
          zone_mapping = state.zone_mappings[control_system_id]?
          if zone_mapping
            key_data = {
              status:            status,
              index:             system_module_mapping[:index],
              module_name:       module_name,
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

    # Scoping
    ###########################################################################

    alias Scoped = Model::Zone | Model::ControlSystem | Model::Driver | Model::Module

    def scope?(model : Scoped) : String?
      case model
      when Model::ControlSystem
        # Check ZoneMappings
      when Model::Driver
        # Check if there's a Driver mapping
        # i.e. driver to module mapping
        # if there isn't drop it
        # when creating the first driver mapping then we should fire a process resource on the driver side
        # That way it will publish the metadata
      when Model::Module
        # Search system module mappings
      when Model::Zone
        # Check if model has any hierarchy tags
      end
    end

    # Mappings
    ###########################################################################

    alias SystemModuleMapping = NamedTuple(control_system_id: String, index: Int32)

    # Wrapper for Mapping state
    class State
      # module_id => [{control_system_id: String, index: Int32}]
      getter module_system_mappings : Hash(String, Array(SystemModuleMapping)) = Hash(String, Array(SystemModuleMapping)).new { [] of SystemModuleMapping }
      # module_id => module_name
      getter module_names : Hash(String, String) = {} of String => String

      # module_id => driver_id
      getter driver_mappings : Hash(String, String) = {} of String => String

      # control_system_id => { hierarchy_tag => zone_id }
      getter system_zone_mappings : Hash(String, Hash(String, String)) = {} of String => Hash(String, String)

      # zone_id => tags
      getter zone_tags : Hash(String, Array(String)) = {} of String => Array(String)
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
