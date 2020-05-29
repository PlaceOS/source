require "redis"

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

    delegate :close, to: redis

    def initialize(@mappings : Mappings, @publisher_manager : PublisherManager, @redis : Redis = Redis.new(url: ENV["REDIS_URL"]?))
    end

    def start
      redis.psubscribe(STATUS_CHANNEL_PATTERN) do |callbacks|
        callbacks.pmessage &->handle_pevent(String, String, String)
      end
    end

    def stop
      redis.punsubscribe(STATUS_CHANNEL_PATTERN)
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
  end
end
