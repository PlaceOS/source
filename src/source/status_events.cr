require "redis"
require "retriable"

require "./mappings"
require "./publishing/publisher"
require "./publishing/publisher_manager"

module PlaceOS::Source
  class StatusEvents
    Log = ::Log.for(self)

    STATUS_CHANNEL_PATTERN = "status/#{Model::Module.table_name}-*"

    getter redis : Redis
    private getter mappings : Mappings
    private getter publisher_managers : Array(PublisherManager)

    private property? stopped : Bool = true

    def initialize(@mappings : Mappings, @publisher_managers : Array(PublisherManager), @redis : Redis = StatusEvents.new_redis)
    end

    def start
      self.stopped = false

      Retriable.retry(
        base_interval: 500.milliseconds,
        max_interval: 5.seconds,
        rand_factor: 0.5
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
