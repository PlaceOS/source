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

    delegate start, stop, to: publisher

    def stats : Hash(String, UInt64)
      {"influx" => publisher.processed}
    end

    def initialize(
      @influx_host : String = INFLUX_HOST || abort("INFLUX_HOST unset"),
      @influx_api_key : String = INFLUX_API_KEY || abort("INFLUX_API_KEY unset"),
      @influx_org : String = INFLUX_ORG,
      @influx_bucket : String = INFLUX_BUCKET,
    )
      client = Flux::Client.new(influx_host, influx_api_key, influx_org)
      @publisher = InfluxPublisher.new(client, influx_bucket)
    end

    # InfluxDB stores a time series rather than current state, so there is
    # nothing retained to remove. History of a renamed Module stays under its
    # old tags, which is what you want from a time series
    def broadcast_delete(message : Publisher::Message)
    end

    def deletes_pending? : Bool
      false
    end

    def broadcast(message : Publisher::Message)
      publisher.message_queue.send(message)
    end
  end
end
