require "action-controller"
require "random"

module PlaceOS::Source
  API_VERSION = "v1"
  APP_NAME    = "source"
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}

  BUILD_TIME   = {{ system("date -u").chomp.stringify }}
  BUILD_COMMIT = {{ env("PLACE_COMMIT") || "DEV" }}

  INFLUX_HOST    = ENV["INFLUX_HOST"]?
  INFLUX_API_KEY = ENV["INFLUX_API_KEY"]?
  INFLUX_ORG     = ENV["INFLUX_ORG"]? || "placeos"
  INFLUX_BUCKET  = ENV["INFLUX_BUCKET"]? || "place"

  DEFAULT_HOST = ENV["PLACE_SOURCE_HOST"]? || "127.0.0.1"
  DEFAULT_PORT = (ENV["PLACE_SOURCE_PORT"]? || 3000).to_i

  HIERARCHY      = ENV["PLACE_HIERARCHY"]?.try(&.split(' ')) || ["org", "region", "building", "level", "area"]
  MQTT_NAMESPACE = "placeos"

  FILTER_SECRET   = ENV["PLACE_FILTER_SECRET"]? || Random::Secure.hex(64)
  DEFAULT_FILTERS = parse_environmental_regex?(ENV["PLACE_DEFAULT_FILTERS"]?) || [/\A([\w+\-].?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i]

  REDIS_URL = ENV["REDIS_URL"]?

  PROD = ENV["ENV"]? == "PROD"

  class_getter? production : Bool = PROD

  protected def self.parse_environmental_regex?(string : String?)
    result = string.try do |s|
      s.split(',').compact_map do |regex_source|
        error = Regex.error?(regex_source)
        if error.nil?
          Regex.new(regex_source)
        else
          Log.error { "#{regex_source} is an invalid regex: #{error}" }
          nil
        end
      end
    end

    result.nil? || result.empty? ? nil : result
  end
end
