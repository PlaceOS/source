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
    private class_getter hierarchy_set : Set(String) = HIERARCHY.to_set

    def initialize(@state : State = State.new)
    end

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
          zone_mapping = state.system_zones[control_system_id]?
          if zone_mapping
            key_data = {
              status:            status,
              index:             system_mapping[:index],
              module_name:       system_mapping[:name],
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
      zone_mapping : Hash(String, String)
    ) : String?
      # Look up zone or replace with _ if not present
      hierarchy_values = HIERARCHY.map { |key| zone_mapping[key]? || "_" }

      # Get concrete values
      scope_value = hierarchy_values.first?

      # Prevent publishing events with unspecified top-level scope
      return if scope_value.nil? || scope_value == "_"

      subhierarchy_values = hierarchy_values[1..]

      module_key = File.join(control_system_id, driver_id, module_name, index.to_s, status)

      "#{MQTT_NAMESPACE}/#{scope_value}/state/#{File.join(subhierarchy_values)}/#{module_key}"
    end

    # Hierarchy and Scoping
    ###########################################################################

    alias Scoped = Model::ControlSystem | Model::Driver | Model::Module | Model::Zone

    # Always check DB when looking up scope.
    #
    # Caches are only for quick lookups when processing events.
    def self.hierarchy_zones(model : Scoped) : Array(Model::Zone)
      case model
      when Model::ControlSystem
        Model::Zone
          .find_all(model.zones.as(Array(String)))
          .reject { |zone| hierarchy_tag?(zone).nil? }
          .to_a
      when Model::Driver
        Model::Module
          .by_driver_id(model.id.as(String))
          .flat_map { |mod| hierarchy_zones(mod) }
          .uniq
          .to_a
      when Model::Module
        Model::ControlSystem
          .by_module_id(model.id.as(String))
          .flat_map { |cs| hierarchy_zones(cs) }
          .uniq
          .to_a
      when Model::Zone
        zone = model.parent || model
        if hierarchy_tag?(zone) == Mappings.scope
          [zone]
        else
          [] of Model::Zone
        end
      end.as(Array(Model::Zone))
    end

    def self.hierarchy_tag?(zone : Model::Zone) : String?
      hierarchy_tags = zone.tags.as(Set(String)) & hierarchy_set

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
        # Clear mappings of all references to control_system_id
        state.system_modules.transform_values do |mappings|
          mappings.reject! { |sys_mod| sys_mod[:control_system_id] == control_system_id }
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
      getter drivers : Hash(String, String) = {} of String => String

      # control_system_id => { hierarchy_tag => zone_id }
      getter system_zones : Hash(String, Hash(String, String)) = {} of String => Hash(String, String)
    end

    @state : State

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
        yield @state
      end
    end
  end
end
