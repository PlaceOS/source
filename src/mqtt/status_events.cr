require "redis"

require "./mappings"
require "./publishing/publisher"
require "./publishing/publisher_manager"

module PlaceOS::MQTT
  class StatusEvents
    STATUS_CHANNEL_PATTERN = "status/*"

    getter redis : Redis
    private getter mappings : Mappings

    delegate :close, to: redis

    def initialize(@publisher_manager : PublisherManager, @mappings : Mappings, @redis : Redis = Redis.new(url: ENV["REDIS_URL"]?))
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
      module_id, status = ModuleEvents.parse_channel(channel)
      key = mappings.state_event_key?(module_id, status)

      publisher_manager.broadcast(Publisher.state(key, payload)) if key
    end

    def self.parse_channel(channel : String) : {String, String}
      _, module_id, status = channel.split('/')
      {module_id, status}
    end
  end
end
