require "flux"
require "mqtt"
require "openssl"
require "random"
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

    alias FieldTypes = Bool | Float64 | String

    abstract class CustomMetrics
      include JSON::Serializable

      # timeseries_hint
      use_json_discriminator "ts_hint", {complex: ComplexMetric}

      # Add these tags and fields to all the values
      property ts_tags : Hash(String, String?)?
      property ts_fields : Hash(String, FieldTypes?)?

      # Allow custom measurement name to be used for entries
      property measurement : String?
    end

    class ComplexMetric < CustomMetrics
      getter ts_hint : String = "complex"

      property value : Array(Hash(String, FieldTypes?))
      property ts_tag_keys : Array(String)?
      property ts_map : Hash(String, String)?

      # allow for a custom timestamp field
      property ts_timestamp : String?
    end

    alias Value = FieldTypes | Hash(String, FieldTypes?) | Hash(String, Hash(String, FieldTypes?)) | Array(Hash(String, FieldTypes?)) | CustomMetrics

    def initialize(@client : Flux::Client, @bucket : String)
    end

    # Write an MQTT event to InfluxDB
    #
    def publish(message : Publisher::Message)
      points = self.class.transform(message)
      points.each do |point|
        Log.trace { {
          measurement: point.measurement,
          timestamp:   point.timestamp.to_s,
          tags:        point.tags.to_json,
          fields:      point.fields.to_json,
        } }
        client.write(bucket, point)
      end
    end

    @@building_timezones = {} of String => Time::Location?
    @@timezone_lock = Mutex.new

    def self.timezone_cache_reset
      loop do
        sleep 1.hour
        @@timezone_lock.synchronize do
          @@building_timezones = {} of String => Time::Location?
        end
      rescue error
        Log.warn(exception: error) { "error clearing timezone cache" }
      end
    end

    def self.timezone_for(building_id : String?) : Time::Location?
      return nil unless building_id && building_id.presence

      @@timezone_lock.synchronize do
        if @@building_timezones.has_key?(building_id)
          return @@building_timezones[building_id]
        end

        if zone = Model::Zone.find_by?(id: building_id)
          @@building_timezones[building_id] = zone.timezone
        end
      end
    rescue error
      Log.warn(exception: error) { "error fetching timezone for zone #{building_id}" }
      nil
    end

    # Generate an InfluxDB Point from an mqtt key + payload
    #
    def self.transform(message : Publisher::Message) : Array(Flux::Point)
      timestamp = message.timestamp
      data = message.data

      # Only Module status events are persisted
      return [] of Flux::Point unless data.is_a? Mappings::Status

      payload = message.payload.presence.try &.gsub(Regex.union(DEFAULT_FILTERS)) do |match_string, _|
        hmac_sha256(match_string)
      end

      # Influx doesn't support `nil`
      if payload.nil? || payload == "null"
        Log.debug { {message: "Influx doesn't support nil", module_id: data.module_id, module_name: data.module_name, status: data.status} }
        return [] of Flux::Point
      end

      # Namespace tags and fields to reduce likely hood that they clash with status names
      tags = HIERARCHY.each_with_object(Hash(String, String).new(initial_capacity: HIERARCHY.size + 2)) do |key, obj|
        obj["pos_#{key}"] = data.zone_mapping[key]? || "_"
      end
      tags["pos_system"] = data.control_system_id
      tags["pos_module"] = data.module_name
      tags["pos_index"] = data.index.to_i64.to_s

      fields = ::Flux::Point::FieldSet.new

      if timezone = timezone_for(data.zone_mapping["region"]?) || timezone_for(data.zone_mapping["building"]?)
        local_time = timestamp.in(timezone)
        tags["pos_day_of_week"] = local_time.day_of_week.to_s
        fields["pos_time_of_day"] = (local_time.hour * 100 + local_time.minute).to_i64
      end

      # https://docs.influxdata.com/influxdb/v2.0/reference/flux/language/lexical-elements/#identifiers
      key = data.status.gsub(/\W/, '_')
      fields["pos_key"] = key

      begin
        case raw = Value.from_json(payload)
        in CustomMetrics then parse_custom(raw, fields, tags, data, timestamp)
        in FieldTypes
          fields[key] = raw
          point = Flux::Point.new!(
            measurement: data.module_name,
            timestamp: timestamp,
            tags: tags,
            pos_driver: data.driver_id,
          ).tap &.fields.merge!(fields)

          [point]
        in Hash(String, FieldTypes?)
          [parse_hash(raw, nil, fields, tags, data, timestamp)].compact
        in Hash(String, Hash(String, FieldTypes?))
          pos_uniq = 0
          raw.compact_map do |hash_key, hash|
            tags["pos_uniq"] = pos_uniq.to_s
            pos_uniq += 1
            parse_hash(hash, hash_key, fields, tags, data, timestamp)
          end
        in Array(Hash(String, FieldTypes?))
          pos_uniq = 0
          raw.compact_map do |hash|
            tags["pos_uniq"] = pos_uniq.to_s
            pos_uniq += 1
            parse_hash(hash, nil, fields, tags, data, timestamp)
          end
        end
      rescue e : JSON::ParseException
        Log.debug { {message: "not an InfluxDB value type", module_id: data.module_id, module_name: data.module_name, status: data.status} }
        [] of Flux::Point
      end
    end

    protected def self.parse_hash(hash, parent_key, fields, tags, data, timestamp)
      return if hash.nil? || (hash = hash.compact).empty?
      measurement = data.module_name

      local_fields = hash.each_with_object(fields.dup) do |(sub_key, value), local|
        next if value.nil?

        sub_key = sub_key.gsub(/\W/, '_')

        if sub_key == "measurement" && value.is_a?(String)
          measurement = value
        else
          local[sub_key] = value
        end
      end

      local_fields["parent_hash_key"] = parent_key unless parent_key.nil?

      Flux::Point.new!(
        measurement: measurement,
        timestamp: timestamp,
        tags: tags.dup,
        pos_driver: data.driver_id,
      ).tap &.fields.merge!(local_fields)
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
      points = Array(Flux::Point).new(initial_capacity: raw.value.size)
      default_measurement = raw.measurement

      raw.value.each_with_index do |val, index|
        # Skip if an empty point
        compacted = val.compact
        next if compacted.empty?
        measurement = default_measurement || data.module_name

        override_timestamp = nil
        if time_key = raw.ts_timestamp
          if time = compacted.delete(time_key).as?(Float64)
            override_timestamp = Time.unix time.to_i64
          end
        end

        # Must include a `pos_uniq` tag for seperating points
        # as per: https://docs.influxdata.com/influxdb/v2.0/write-data/best-practices/duplicate-points/#add-an-arbitrary-tag
        local_tags = tags.dup
        local_tags["pos_uniq"] = index.to_s

        points << build_custom_point(measurement, data, fields, local_tags, compacted, override_timestamp || timestamp, ts_map, raw.ts_tag_keys)
      end

      points
    end

    protected def self.build_custom_point(measurement, data, fields, local_tags, compacted, timestamp, ts_map, ts_tag_keys)
      measurement_value = measurement
      # Add the fields
      local_fields = fields.dup
      compacted.each do |sub_key, value|
        sub_key = (ts_map[sub_key]? || sub_key).gsub(/\W/, '_')
        if sub_key == "measurement" && value.is_a?(String)
          measurement_value = value
        else
          local_fields[sub_key] = value
        end
      end

      # convert fields to tags as required
      if ts_tag_keys
        ts_tag_keys.each do |field|
          field_value = local_fields.delete field
          # might be `false`
          if !field_value.nil?
            local_tags[field] = field_value.to_s
          end
        end
      end

      Flux::Point.new!(
        measurement: measurement_value,
        timestamp: timestamp,
        tags: local_tags,
        pos_driver: data.driver_id,
      ).tap &.fields.merge!(local_fields)
    end

    protected def self.hmac_sha256(data : String)
      OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, FILTER_SECRET, data)
    end
  end
end
