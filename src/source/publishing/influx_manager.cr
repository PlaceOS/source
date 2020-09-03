require "flux"

require "./influx_publisher"
require "./publisher"
require "./publisher_manager"

module PlaceOS::Source
  class InfluxManager
    include PublisherManager

    getter publisher : InfluxPublisher
    private getter influx_host : String
    private getter influx_api_key : String
    private getter influx_org : String
    private getter influx_bucket : String

    def initialize(
      @influx_host : String = INFLUX_HOST || abort("INFLUX_HOST unset"),
      @influx_api_key : String = INFLUX_API_KEY || abort("INFLUX_API_KEY unset"),
      @influx_org : String = INFLUX_ORG,
      @influx_bucket : String = INFLUX_BUCKET
    )
      client = Flux::Client.new(influx_host, influx_api_key, influx_org)
      @publisher = InfluxPublisher.new(client, influx_bucket)
    end

    def broadcast(message : Publisher::Message)
      publisher.message_queue.send(message)
    end

    def start
    end

    def stop
    end
  end
end
