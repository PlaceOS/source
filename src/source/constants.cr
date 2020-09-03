require "action-controller"
require "log_helper"
require "random"

module PlaceOS::Source
  API_VERSION = "v1"
  APP_NAME    = "mqtt"
  VERSION     = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  DEFAULT_MQTT_HOST = ENV["PLACE_MQTT_HOST"]? || "127.0.0.1"
  DEFAULT_MQTT_PORT = (ENV["PLACE_MQTT_PORT"]? || 3000).to_i

  HIERARCHY      = ENV["PLACE_MQTT_HIERARCHY"]?.try(&.split(' ')) || ["org", "building", "level", "area"]
  MQTT_NAMESPACE = "placeos"

  FILTER_SECRET   = ENV["PLACE_FILTER_SECRET"]? || Random::Secure.hex(64)
  DEFAULT_FILTERS = parse_environmental_regex(ENV["PLACE_DEFAULT_FILTERS"]) || [/\A([\w+\-].?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i]

  REDIS_URL = ENV["REDIS_URL"]?

  PROD = ENV["ENV"]? == "PROD"

  LOG_BACKEND = ActionController.default_backend

  def self.production?
    PROD
  end

  protected def self.parse_environmental_regex?(string : String?)
    result = string.try do |s|
      s.split(',').compact_map do |regex_source|
        error = Regex.error(regex_source)
        if error.nil?
          Regex.new(regex_source)
        else
          Log.error { "#{regex_source} is an invalid regex: #{error}" }
        end
      end
    end

    result.empty? ? nil : result
  end
end
