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

    # Generates a key if event is to be published
    #
    def state_event_key?(module_id : String, status : String) : String?
      abort "unimplemented"
    end

    # Construct a Module `state` event key prefix
    #
    # If a ZoneMapping is missing, the corresponding hierarchy value will be '_'
    def self.state_event_prefix(driver_id : String, zone_mapping : ZoneMapping, module_mapping : ModuleMapping) : String?
      module_key = File.join(driver_id, module_mapping[:name], module_mapping[:index])

      # Look up zone or replace with _ if not present
      hierarchy_values = HIERARCHY.map { |key| zone_mapping[key]? || "_" }

      # Get concrete values
      scope_value = hierarchy_values.first?

      # Prevent publishing unspecified top level scope events
      return if scope_value.nil? || scope_value == "_"

      subhierarchy_values = hierarchy_values[1..]

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

    alias ModuleMapping = NamedTuple(system_id: String, name: String, index: String)

    # module_id => driver_id
    @driver_mappings : Hash(String, String) = {} of String => String

    # module_id => [{system_id: String, name: String, index: String}]
    @module_mappings : Hash(String, Array(ModuleMapping)) = Hash(String, Array(ModuleMapping)).new { [] of ModuleMapping }

    # control_system_id => { hierarchy_tag => zone_id }
    @system_zone_mappings : Hash(String, Hash(String, String)) = {} of String => Hash(String, String)

    # zone_id => tags
    @zone_tags : Hash(String, Array(String)) = {} of String => Array(String)

    {% for mapping in [:driver_mappings, :module_mappings, :system_zone_mappings, :zone_tags] %}
      private getter {{mapping.id}}_lock : RWLock = RWLock.new

      # Synchronized read access to {{ mapping.stringify }}
      def read_{{mapping.id}}
        {{mapping.id}}_lock.read do
          yield @{{mapping.id}}
        end
      end

      # Synchronized write access to {{ mapping.stringify }}
      def write_{{mapping.id}}
        {{mapping.id}}_lock.write do
          yield @{{mapping.id}}
        end
      end
    {% end %}
  end
end
