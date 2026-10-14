require "./mappings"
require "./publishing/*"
require "./router/*"

module PlaceOS::Source
  class Manager
    Log = ::Log.for(self)

    getter control_system_router : Router::ControlSystem
    getter driver_router : Router::Driver
    getter module_router : Router::Module
    getter zone_router : Router::Zone

    getter status_events : StatusEvents

    getter publisher_managers : Array(PublisherManager)

    getter? started = false

    class_property instance : self { new }

    def initialize(
      @publisher_managers : Array(PublisherManager) = [] of PublisherManager,
      @mappings : Mappings = Mappings.new,
    )
      @control_system_router = Router::ControlSystem.new(mappings, publisher_managers)
      @driver_router = Router::Driver.new(mappings, publisher_managers)
      @module_router = Router::Module.new(mappings, publisher_managers)
      @zone_router = Router::Zone.new(mappings, publisher_managers)
      @status_events = StatusEvents.new(mappings, publisher_managers)
    end

    def start
      return if started?
      @started = true

      # Start publisher managers first to establish connections
      Log.info { "registering Publishers" }
      publisher_managers.each(&.start)

      # Acquire the Zones (hierarchy) first
      Log.info { "starting Zone router" }
      zone_router.start

      # Map ControlSystems beneath Zones
      Log.info { "starting ControlSystem router" }
      control_system_router.start

      # Map to driver_ids and module_names
      Log.info { "starting Module router" }
      module_router.start

      # Publish any relevant driver metadata
      Log.info { "starting Driver router" }
      driver_router.start

      # Setup callback for new broker connections to trigger state resync
      publisher_managers.each do |manager|
        if manager.is_a?(MqttBrokerManager)
          manager.on_broker_ready = ->(broker_id : String) {
            Log.info { "triggering state resync for new Broker<#{broker_id}>" }
            spawn { status_events.resync_state }
          }
        end
      end

      Log.info { "listening for Module state events" }
      spawn { status_events.start }

      Fiber.yield
    end

    # Resync
    ###########################################################################

    # Where the last resync got to
    struct ResyncStatus
      include JSON::Serializable

      enum State
        Idle
        Clearing
        Resyncing
        Complete
        Failed
      end

      getter state : State
      # whether everything retained was removed first
      getter? clear : Bool
      getter started_at : Time?
      getter finished_at : Time?
      # retained topics removed, when clearing
      getter cleared : Int64
      # models whose metadata was published again
      getter metadata : Int32
      getter error : String?

      def initialize(@state = State::Idle, @clear = false, @started_at = nil, @finished_at = nil, @cleared = 0_i64, @metadata = 0, @error = nil)
      end

      def running? : Bool
        state.clearing? || state.resyncing?
      end

      def copy_with(**changes) : self
        ResyncStatus.new(**{
          state:       @state,
          clear:       @clear,
          started_at:  @started_at,
          finished_at: @finished_at,
          cleared:     @cleared,
          metadata:    @metadata,
          error:       @error,
        }.merge(changes))
      end
    end

    private getter resync_lock = Mutex.new
    @resync_status = ResyncStatus.new

    def resync_status : ResyncStatus
      resync_lock.synchronize { @resync_status }
    end

    private def resync_status=(status : ResyncStatus)
      resync_lock.synchronize { @resync_status = status }
    end

    # Publishes everything to the MQTT brokers again: every Module's state and
    # every model's metadata. With `clear`, everything source publishes is
    # removed from the brokers first, for when what they hold has drifted.
    #
    # Runs in the background, one at a time. Returns false if one is running.
    def resync(clear : Bool = false) : Bool
      resync_lock.synchronize do
        return false if @resync_status.running?
        @resync_status = ResyncStatus.new(
          state: clear ? ResyncStatus::State::Clearing : ResyncStatus::State::Resyncing,
          clear: clear,
          started_at: Time.utc,
        )
      end
      spawn { run_resync(clear) }
      true
    end

    private def run_resync(clear : Bool) : Nil
      # what is resynced is the state the initial sync has read
      until status_events.initial_sync_complete?
        sleep 1.second
      end

      Log.info { {message: "resyncing MQTT brokers", clear: clear} }
      if clear
        cleared = status_events.clear_retained
        self.resync_status = resync_status.copy_with(state: ResyncStatus::State::Resyncing, cleared: cleared)
      end

      metadata = zone_router.republish_metadata +
                 control_system_router.republish_metadata +
                 driver_router.republish_metadata
      status_events.resync_state

      self.resync_status = resync_status.copy_with(
        state: ResyncStatus::State::Complete,
        metadata: metadata,
        finished_at: Time.utc,
      )
      Log.info { {message: "resynced MQTT brokers", clear: clear, metadata: metadata.to_s} }
    rescue error
      Log.error(exception: error) { "resyncing MQTT brokers" }
      self.resync_status = resync_status.copy_with(
        state: ResyncStatus::State::Failed,
        error: error.message || error.class.name,
        finished_at: Time.utc,
      )
    end

    def stop
      return unless started?

      @started = false
      status_events.stop
      publisher_managers.each &.stop
      control_system_router.stop
      driver_router.stop
      module_router.stop
      zone_router.stop
    end
  end
end
