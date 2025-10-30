require "mutex"
require "redis"
require "simple_retry"

require "placeos-driver/storage"
require "./mappings"
require "./publishing/publisher"
require "./publishing/publisher_manager"

module PlaceOS::Source
  class StatusEvents
    Log = ::Log.for(self)

    STATUS_CHANNEL_PATTERN      = "status/#{Model::Module.table_name}-*"
    MAX_CONTAINER_SIZE          = 50_000
    BATCH_SIZE                  =    100
    PROCESSING_INTERVAL         = 100.milliseconds
    CONTAINER_WARNING_THRESHOLD = MAX_CONTAINER_SIZE * 0.8

    private getter! redis : Redis
    private getter mappings : Mappings
    private getter publisher_managers : Array(PublisherManager)

    private property? stopped : Bool = true

    private getter sync_lock = Mutex.new(:reentrant)

    alias EventKey = NamedTuple(source: Symbol, mod_id: String, status: String)
    alias EventValue = NamedTuple(pattern: String, payload: String, timestamp: Time)
    private getter event_container = Hash(EventKey, EventValue).new
    private getter event_queue = [] of EventKey

    def initialize(@mappings : Mappings, @publisher_managers : Array(PublisherManager))
    end

    def start
      self.stopped = false
      spawn { update_values }
      spawn { process_events }

      SimpleRetry.try_to(
        base_interval: 500.milliseconds,
        max_interval: 5.seconds,
        randomise: 500.milliseconds
      ) do
        unless stopped?
          @redis = new_redis = StatusEvents.new_redis
          new_redis.psubscribe(STATUS_CHANNEL_PATTERN) do |callbacks|
            callbacks.pmessage &->handle_pevent(String, String, String)
          end
          raise "subscription loop exited, restarting loop" unless stopped?
        end
      end
    end

    def stop
      self.stopped = true

      return unless @redis
      begin
        redis.punsubscribe(STATUS_CHANNEL_PATTERN)
      rescue
      end

      redis.close
    end

    def update_values
      mods_mapped = 0_u64
      status_updated = 0_u64
      pattern = "initial_sync"
      PlaceOS::Model::Module.order(id: :asc).all.in_groups_of(64, reuse: true) do |modules|
        modules.each do |mod|
          next unless mod
          mods_mapped += 1_u64
          module_id = mod.id.to_s
          store = PlaceOS::Driver::RedisStorage.new(module_id)
          store.each do |key, value|
            status_updated += 1_u64
            add_event({source: :db, mod_id: module_id, status: key}, {pattern: pattern, payload: value, timestamp: Time.utc})
          end

          # Backpressure if event container is growing too fast
          if event_container.size >= MAX_CONTAINER_SIZE / 2
            until event_container.size < MAX_CONTAINER_SIZE / 4
              sleep 10.milliseconds
            end
          end
        rescue error
          Log.warn(exception: error) { "error syncing #{mod.try(&.id)}" }
        end
      end
      Log.info { {
        message: "initial status sync complete",
        modules: mods_mapped.to_s,
        values:  status_updated.to_s,
      } }
    end

    protected def handle_pevent(pattern : String, channel : String, payload : String)
      begin
        module_id, status = StatusEvents.parse_channel(channel)
      rescue error : IndexError
        Log.error(exception: error) { {
          message: "Error parsing channel. Skipping redis pevent processing",
          pattern: pattern,
          channel: channel,
        } }
        return
      end
      add_event({source: :redis, mod_id: module_id, status: status}, {pattern: pattern, payload: payload, timestamp: Time.utc})
    end

    private def add_event(key : EventKey, value : EventValue)
      synchronize do
        has_key = event_container.has_key?(key)
        event_container[key] = value
        event_queue << key unless has_key
      end
    end

    protected def process_events
      until stopped?
        begin
          batch = build_batch
          if batch.empty?
            sleep PROCESSING_INTERVAL
          else
            process_batch(batch)
            Fiber.yield
          end
        rescue error
          Log.error(exception: error) { "error processing events" }
          sleep PROCESSING_INTERVAL
        end
      end
    end

    private def build_batch : Array({EventKey, EventValue})
      synchronize do
        keys = event_queue.shift(BATCH_SIZE)
        keys.map { |key| {key, event_container.delete(key).as(EventValue)} }
      end
    end

    private def process_batch(batch)
      batch.each do |(key, value)|
        process_pevent(value[:pattern], key[:mod_id], key[:status], value[:payload], value[:timestamp])
      end
    rescue error
      Log.error(exception: error) { "Error processing event batch" }
    end

    protected def process_pevent(pattern : String, module_id : String, status : String, payload : String, timestamp : Time)
      events = mappings.status_events?(module_id, status)

      Log.debug { {
        message:   "redis pevent",
        pattern:   pattern,
        module_id: module_id,
        status:    status,
      } }

      events.try &.each do |event|
        message = Publisher::Message.new(event, payload, timestamp)
        publisher_managers.each do |manager|
          Log.trace { "broadcasting message to #{manager.class}" }
          manager.broadcast(message)
        end
      end
    end

    def self.parse_channel(channel : String) : {String, String}
      _, module_id, status = channel.split('/')
      {module_id, status}
    end

    protected def self.new_redis
      Redis.new(url: REDIS_URL)
    end

    private def synchronize(&)
      sync_lock.synchronize do
        yield
      end
    end
  end
end
