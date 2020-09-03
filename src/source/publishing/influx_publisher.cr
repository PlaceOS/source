require "flux"
require "mqtt"
require "openssl"
require "random"
require "simple_retry"
require "time"

require "./publisher"

module PlaceOS::Source
  # Publish Module status events to InfluxDB
  #
  # Follows the hiearchy "org", "building", "level", "area"
  # Note: Currently, dynamic Zone hierarchies are unsupported for InfluxDB
  class InfluxPublisher < Publisher
    getter client : Flux::Client
    getter bucket : String

    def initialize(@client : Flux::Client, @bucket : String)
    end

    # Write an MQTT event to InfluxDB
    #
    def publish(message : Publisher::Message)
      point = InfluxManager.transform(message)
      if point
        Log.debug { {
          measurement: point.measurement,
          timestamp:   point.timestamp,
          tags:        point.tags,
          fields:      point.fields,
        } }
        client.write(bucket, point)
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
        :org      => data.zone_mapping["org"],
        :building => data.zone_mapping["building"],
      }.compact

      Flux::Point.new!(
        measurement: data.module_name,
        timestamp: timestamp,
        tags: tags,
        level: data.zone_mapping["level"],
        area: data.zone_mapping["area"],
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
