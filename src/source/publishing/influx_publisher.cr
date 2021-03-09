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

    abstract class CustomMetrics
      include JSON::Serializable

      # timeseries_hint
      use_json_discriminator "ts_hint", {complex: ComplexMetric}

      # Add these tags and fields to all the values
      property ts_tags : Hash(String, String?)?
      property ts_fields : Hash(String, Flux::Point::FieldType?)?
    end

    class ComplexMetric < CustomMetrics
      getter ts_hint : String = "complex"

      property value : Array(Hash(String, Flux::Point::FieldType?))
      property ts_tag_keys : Array(String)?
      property ts_map : Hash(String, String)?
    end

    alias Value = Flux::Point::FieldType | Hash(String, Flux::Point::FieldType?) | CustomMetrics

    def initialize(@client : Flux::Client, @bucket : String)
    end

    # Write an MQTT event to InfluxDB
    #
    def publish(message : Publisher::Message)
      points = self.class.transform(message)
      points.each do |point|
        Log.debug { {
          measurement: point.measurement,
          timestamp:   point.timestamp.to_s,
          tags:        point.tags.to_json,
          fields:      point.fields.to_json,
        } }
        client.write(bucket, point)
      end
    end

    # Generate an InfluxDB Point from an mqtt key + payload
    #
    def self.transform(message : Publisher::Message, timestamp : Time = Publisher.timestamp) : Array(Flux::Point)
      data = message.data

      # Only Module status events are persisted
      return [] of Flux::Point unless data.is_a? Mappings::Status

      payload = message.payload.try &.gsub(Regex.union(DEFAULT_FILTERS)) do |match_string, _|
        hmac_sha256(match_string)
      end

      # Namespace tags and fields to reduce likely hood that they clash with status names
      tags = HIERARCHY.each_with_object({} of String => String) do |key, obj|
        obj["pos_#{key}"] = data.zone_mapping[key]? || "_"
      end

      fields = ::Flux::Point::FieldSet.new

      # https://docs.influxdata.com/influxdb/v2.0/reference/flux/language/lexical-elements/#identifiers
      key = data.status.gsub(/\W/, '_')
      fields["pos_key"] = key

      # Influx doesn't support nil values
      if payload.nil?
        Log.info { {message: "Influx doesn't support nil values", status: key} }
        return [] of Flux::Point
      end

      begin
        raw = Value.from_json(payload)

        case raw
        in Flux::Point::FieldType
          fields[key] = raw
        in Hash(String, Flux::Point::FieldType?)
          compacted = raw.compact
          return [] of Flux::Point if compacted.empty?

          compacted.each do |sub_key, value|
            sub_key = sub_key.gsub(/\W/, '_')
            fields[sub_key] = value
          end
        in CustomMetrics
          return parse_custom(raw, fields, tags, data, timestamp)
        end
      rescue e : JSON::ParseException
        Log.info { {message: "could not extract InfluxDB value type from status value", status: data.status, payload: payload} }
        return [] of Flux::Point
      end

      point = Flux::Point.new!(
        measurement: data.module_name,
        timestamp: timestamp,
        tags: tags,
        pos_system: data.control_system_id,
        pos_driver: data.driver_id,
        pos_index: data.index.to_i64,
      )
      point.fields.merge!(fields)
      [point]
    end

    protected def self.parse_custom(raw, fields, tags, data, timestamp)
      # Add the tags and fields going to all points
      if ts_tags = raw.ts_tags
        tags.merge!(ts_tags.compact)
      end
      if ts_fields = raw.ts_fields
        fields.merge!(ts_fields.compact)
      end

      ts_map = raw.ts_map || {} of String => String
      points = [] of Flux::Point

      raw.value.each_with_index do |val, index|
        # Skip if an empty point
        compacted = val.compact
        next if compacted.empty?

        # Add the fields
        local_fields = fields.dup
        compacted.each do |sub_key, value|
          sub_key = (ts_map[sub_key]? || sub_key).gsub(/\W/, '_')
          local_fields[sub_key] = value
        end

        # must include a `pos_uniq` tag for seperating points
        # as per: https://docs.influxdata.com/influxdb/v2.0/write-data/best-practices/duplicate-points/#add-an-arbitrary-tag
        local_tags = tags.dup
        local_tags["pos_uniq"] = index.to_s

        # convert fields to tags as required
        if ts_tag_keys = raw.ts_tag_keys
          ts_tag_keys.each do |field|
            field_value = local_fields.delete field
            # might be `false`
            if !field_value.nil?
              local_tags[field] = field_value.to_s
            end
          end
        end

        point = Flux::Point.new!(
          measurement: data.module_name,
          timestamp: timestamp,
          tags: local_tags,
          pos_system: data.control_system_id,
          pos_driver: data.driver_id,
          pos_index: data.index.to_i64,
        )
        point.fields.merge!(local_fields)
        points << point
      end

      points
    end

    protected def self.hmac_sha256(data : String)
      OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, FILTER_SECRET, data)
    end
  end
end
