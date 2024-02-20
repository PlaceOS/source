require "redis"
require "simple_retry"

require "placeos-driver/storage"
require "./mappings"
require "./publishing/publisher"
require "./publishing/publisher_manager"

module PlaceOS::Source
  class StatusEvents
    Log = ::Log.for(self)

    STATUS_CHANNEL_PATTERN = "status/#{Model::Module.table_name}-*"

    private getter! redis : Redis
    private getter mappings : Mappings
    private getter publisher_managers : Array(PublisherManager)

    private property? stopped : Bool = true

    def initialize(@mappings : Mappings, @publisher_managers : Array(PublisherManager))
    end

    def start
      self.stopped = false
      spawn(same_thread: true) { update_values }

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
          break unless mod
          mods_mapped += 1_u64
          store = PlaceOS::Driver::RedisStorage.new(mod.id.to_s)
          store.each do |key, value|
            status_updated += 1_u64
            begin
              if key.split('/').size < 3
                Log.warn { {
                  message: "Channel missing module information. Skipping redis_pevent processing",
                  pattern: pattern,
                  channel: key,
                } }
                next
              end
              handle_pevent(pattern: pattern, channel: key, payload: value)
            rescue error
              Log.error(exception: error) { {
                message: "publishing initial state",
                pattern: pattern,
                channel: key,
              } }
            end
          end
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
          message: "Channel missing module information. Skipping redis pevent processing",
          pattern: pattern,
          channel: channel,
        } }
        return
      end
      events = mappings.status_events?(module_id, status)

      Log.debug { {
        message: "redis pevent",
        pattern: pattern,
        channel: channel,
      } }

      events.try &.each do |event|
        message = Publisher::Message.new(event, payload)
        publisher_managers.each do |manager|
          Log.trace { "broadcasting message to #{manager.class}" }
          spawn { manager.broadcast(message) }
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
  end
end
