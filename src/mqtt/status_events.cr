require "redis"
require "simple_retry"

require "./mappings"
require "./publishing/publisher"
require "./publishing/publisher_manager"

module PlaceOS::MQTT
  class StatusEvents
    Log = ::Log.for("mqtt.status_events")

    STATUS_CHANNEL_PATTERN = "status/*"

    getter redis : Redis
    private getter mappings : Mappings
    private getter publisher_manager : PublisherManager

    private property? stopped : Bool = true

    def initialize(@mappings : Mappings, @publisher_manager : PublisherManager, @redis : Redis = StatusEvents.new_redis)
    end

    def start
      self.stopped = false

      SimpleRetry.try_to(
        base_interval: 1.second,
        max_interval: 5.seconds,
        randomise: 500.milliseconds
      ) do
        begin
          redis.psubscribe(STATUS_CHANNEL_PATTERN) do |callbacks|
            callbacks.pmessage &->handle_pevent(String, String, String)
          end
        ensure
          @redis = StatusEvents.new_redis unless stopped?
        end
      end
    end

    def stop
      self.stopped = true

      redis.punsubscribe(STATUS_CHANNEL_PATTERN)
      redis.close
    end

    protected def handle_pevent(pattern : String, channel : String, payload : String)
      module_id, status = StatusEvents.parse_channel(channel)
      keys = mappings.state_event_keys?(module_id, status)
      if keys
        keys.each do |key|
          publisher_manager.broadcast(Publisher.state(key, payload))
        end
      end
    end

    def self.parse_channel(channel : String) : {String, String}
      _, module_id, status = channel.split('/')
      {module_id, status}
    end

    protected def self.new_redis
      Redis.new(url: ENV["REDIS_URL"]?)
    end
  end
end
