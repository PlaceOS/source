require "action-controller"
require "log_helper"

module PlaceOS::MQTT
  API_VERSION = "v1"
  APP_NAME    = "mqtt"
  VERSION     = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  HIERARCHY = ENV["PLACE_MQTT_HIERARCHY"]?.try(&.split(' ')) || ["org", "building", "level", "area"]

  LOG_BACKEND = ActionController.default_backend
end
