require "placeos-models/control_system"
require "placeos-models/zone"
require "placeos-resource"

require "../mappings"
require "../publishing/publish_metadata"
require "../publishing/publisher_manager"

module PlaceOS::Source::Router
  # ControlSystem router (If correctly scoped)
  # - Publishes metadata
  # - Listens for changes to the `zones` array
  #   + maintain system_zones
  # - Listens for changes to the `modules` array
  #   + maintain system_modules
  # - Remove references to ControlSystem on destroy
  class ControlSystem < Resource(PlaceOS::Model::ControlSystem)
    include PublishMetadata(PlaceOS::Model::ControlSystem)
    Log = ::Log.for(self)

    private getter mappings : Mappings
    private getter publisher_managers : Array(PublisherManager)

    def initialize(@mappings : Mappings, @publisher_managers : Array(PublisherManager))
      super()
    end

    # Events are processed concurrently and in no particular order: pg-orm and
    # `Resource` each handle every change on a fiber of its own. So two quick
    # edits to one system can be handled newest first, and an event's own copy
    # of the system, and its `*_changed?` flags, cannot be trusted to be the
    # latest. Each event instead takes this lock, reads the system as it is
    # now, and rebuilds its mappings from that: whichever runs last leaves
    # them matching the database
    private getter sync_lock = Mutex.new

    def handle_create(control_system : PlaceOS::Model::ControlSystem) : Resource::Result
      # While the routers load, events are only the rows just read, one per
      # system, and change events wait until loading is done. So the row can
      # be used as it is, rather than read again for every system
      loaded = control_system unless startup_finished?
      sync(control_system.id.as(String), loaded)
    end

    def handle_update(control_system : PlaceOS::Model::ControlSystem) : Resource::Result
      sync(control_system.id.as(String))
    end

    def handle_delete(control_system : PlaceOS::Model::ControlSystem) : Resource::Result
      sync(control_system.id.as(String))
    end

    # Brings the mappings for a system into line with the database, and has
    # what is retained for it reconciled if they changed.
    #
    # Zones are topic segments, and a module's index is its position among the
    # system's modules of the same name, so a change to either moves topics.
    # Reconciling removes the old ones and publishes current values at the new
    # ones — which also covers a module whose state was written before the
    # system mapped it, and so was published nowhere.
    #
    # `loaded` is the system as the initial load read it. Nothing is
    # reconciled for it: status events have not started, nothing is published
    # yet to take away, and their initial sync publishes every Module against
    # the mappings built here. Queueing them all would read the state of every
    # Module a second time, in one batch
    #
    # `loaded_zones` are the system's hierarchy zones, when already read with it
    def sync(
      control_system_id : String,
      loaded : PlaceOS::Model::ControlSystem? = nil,
      loaded_zones : Array(PlaceOS::Model::Zone)? = nil,
    ) : Resource::Result
      sync_lock.synchronize do
        current = loaded || PlaceOS::Model::ControlSystem.find?(control_system_id)

        zones = current.try { |cs| Router::ControlSystem.system_zones(cs, loaded ? loaded_zones : nil) }
        modules = current.try { |cs| Router::ControlSystem.system_modules(cs) }

        changed = mappings.read do |state|
          state.system_zones[control_system_id]? != zones ||
            mappings.system_modules_for(control_system_id) != (modules || {} of String => Mappings::SystemModule)
        end

        if zones && modules
          mappings.write { |state| state.system_zones[control_system_id] = zones }
          mappings.set_system_modules(control_system_id, modules)
        else
          mappings.write(&.system_zones.delete(control_system_id))
          mappings.remove_system_modules(control_system_id)
        end

        mappings.reconcile_systems({control_system_id}) if changed && loaded.nil?
      end

      Resource::Result::Success
    end

    # Publishes the metadata of every system in scope again. Scope is read
    # from the mappings, which hold every system's hierarchy
    def republish_metadata : Int32
      count = 0
      Mappings.each_model(PlaceOS::Model::ControlSystem) do |control_system|
        next unless mappings.scoped_system?(control_system.id.as(String))
        publish_metadata(control_system)
        count += 1
      end
      count
    end

    def process_resource(action : Resource::Action, resource : PlaceOS::Model::ControlSystem) : Resource::Result
      control_system = resource

      hierarchy_zones = Mappings.hierarchy_zones(control_system)

      # NOTE:: an update is processed even when the system is in no scoped zone
      # any more: it may have just been moved out of one, and what it published
      # while it was in scope has to go
      return Resource::Result::Skipped if hierarchy_zones.empty? && action.created?

      publish_metadata(hierarchy_zones, control_system)

      case action
      in .created?
        # while loading, the zones just read are the system's hierarchy, so
        # they are not read again to map it
        return handle_create(control_system) if startup_finished?
        sync(control_system.id.as(String), control_system, hierarchy_zones)
      in .updated?
        handle_update(control_system)
      in .deleted?
        handle_delete(control_system)
      end
    end

    def self.system_zones(control_system : PlaceOS::Model::ControlSystem, zones : Array(PlaceOS::Model::Zone)? = nil) : Hash(String, String)
      # Generate zone mappings
      # NOTE: Duplication decessary due to compiler bug with iteration
      zone_mappings = if !zones.nil?
                        zones.compact_map do |zone|
                          tag = Mappings.hierarchy_tag?(zone)
                          Mappings.zone_mapping(zone.id.as(String), tag) unless tag.nil?
                        end
                      else
                        _system_zones(control_system).compact_map do |zone|
                          tag = Mappings.hierarchy_tag?(zone)
                          Mappings.zone_mapping(zone.id.as(String), tag) unless tag.nil?
                        end
                      end

      # Merge individual zone_mappings into a single zone mapping hash
      zone_mappings.reduce({} of String => String) do |acc, mapping|
        acc.merge!(mapping)
      end
    end

    # Map from `module_id` => {control_system_id: String, name: String, index: Int32}
    def self.system_modules(control_system : PlaceOS::Model::ControlSystem, modules : Array(PlaceOS::Model::Module)? = nil) : Hash(String, Mappings::SystemModule)
      control_system_id = control_system.id.as(String)

      # module_name => [module_id]
      # Order module_ids, grouped by resolved name
      # NOTE: Duplication decessary due to compiler bug with iteration
      grouped = if !modules.nil?
                  modules.each_with_object(Hash(String, Array(String)).new { |h, k| h[k] = [] of String }) { |mod, mapping|
                    mapping[mod.resolved_name] << mod.id.as(String)
                  }
                else
                  _system_modules(control_system).each_with_object(Hash(String, Array(String)).new { |h, k| h[k] = [] of String }) { |mod, mapping|
                    mapping[mod.resolved_name] << mod.id.as(String)
                  }
                end

      # module_id => Mappings::SystemModule
      # Generate SystemModule mappings
      grouped.each_with_object({} of String => Mappings::SystemModule) do |(name, ids), mapping|
        ids.each_with_index(offset: 1) do |id, index|
          mapping[id] = {name: name, control_system_id: control_system_id, index: index}
        end
      end
    end

    # Get zones
    protected def self._system_zones(control_system : PlaceOS::Model::ControlSystem)
      zone_list = control_system.zones || [] of String
      PlaceOS::Model::Zone.find_all(zone_list)
    end

    # Get modules, in the system's order.
    #
    # NOTE:: the order is load-bearing: a Module's index is its position among
    # the system's Modules of the same name. `find_all` returns rows in
    # whatever order the database does, so indexes used to follow the Module
    # ids rather than the system, and reordering a system changed nothing that
    # was published
    protected def self._system_modules(control_system : PlaceOS::Model::ControlSystem)
      module_ids = control_system.modules || [] of String
      found = PlaceOS::Model::Module.find_all(module_ids).to_h { |mod| {mod.id.as(String), mod} }
      module_ids.compact_map { |id| found[id]? }
    end
  end
end
