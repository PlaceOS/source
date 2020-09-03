require "flux"
require "mqtt"
require "openssl"
require "random"
require "simple_retry"
require "time"

require "./publisher"

module PlaceOS::Source
  class InfluxManager
    include PublisherManager

    def broadcast(message : Publisher::Message)
    end

    def start
    end

    def stop
    end
  end

  # Publish Module status events to InfluxDB
  #
  # Follows the hiearchy "org", "building", "level", "area"
  # Note: Currently, dynamic Zone hierarchies are unsupported for InfluxDB
  class InfluxPublisher < Publisher
    # Write an MQTT event to InfluxDB
    #
    def publish(message : Publisher::Message)
      point = Source.transform(message)
      if point
        Log.debug { {
          measurement: point.measurement,
          timestamp:   point.timestamp,
          tags:        point.tags,
          fields:      point.fields,
        } }
        Flux.write(point)
      end
    end

    # Generate an InfluxDB Point from an mqtt key + payload
    #
    def self.transform(message : Publisher::Message, timestamp : Time = self.timesamp) : Flux::Point?
      data = message.data
      # Only Module status events are persisted
      return unless data.is_a? Mappings::Status

      payload = data.payload.gsub(Regex.union(DEFAULT_FILTERS)) do |match_string, _|
        hmac_sha256(match_string)
      end

      tags = Hash(Symbol, String?){
        :org      => data.zone_mappings["org"],
        :building => data.zone_mappings["building"],
      }.compact

      Flux::Point.new!(
        measurement: data.module_name,
        timestamp: timestamp,
        tags: tags,
        level: data.zone_mappings["level"],
        area: data.zone_mappings["area"],
        system: data.control_system_id,
        driver: data.driver_id,
        index: data.index,
        state: data.status,
        value: payload,
      )
    end

    protected def self.hmac_sha256(data : String)
      OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, FILTER_SECRET, data)
    end
  end
end
