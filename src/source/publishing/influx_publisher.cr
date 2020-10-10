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

    alias Value = Bool | Float64 | Int64 | String | Nil

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
    def self.transform(message : Publisher::Message, timestamp : Time = Publisher.timestamp) : Flux::Point?
      data = message.data
      # Only Module status events are persisted
      return unless data.is_a? Mappings::Status

      payload = message.payload.try &.gsub(Regex.union(DEFAULT_FILTERS)) do |match_string, _|
        hmac_sha256(match_string)
      end

      # Namespace tags and fields to reduce likely hood that they clash with status names
      tags = Hash(Symbol, String?){
        :pos_org      => data.zone_mapping["org"],
        :pos_building => data.zone_mapping["building"],
      }.compact

      value = begin
        raw = JSON.parse(payload).raw unless payload.nil?

        if raw.is_a?(Value)
          raw
        else
          Log.info { "could not extract InfluxDB value type from status value" }
          nil
        end
      rescue e : JSON::ParseException
        Log.warn { {message: "failed to parse status event after filtering", payload: payload} }
        nil
      end

      point = Flux::Point.new!(
        measurement: data.module_name,
        timestamp: timestamp,
        tags: tags,
        pos_level: data.zone_mapping["level"],
        pos_area: data.zone_mapping["area"],
        pos_system: data.control_system_id,
        pos_driver: data.driver_id,
        pos_index: data.index.to_i64,
      )
      point.fields[%("#{data.status}")] = value
      point
    end

    protected def self.hmac_sha256(data : String)
      OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, FILTER_SECRET, data)
    end
  end
end
