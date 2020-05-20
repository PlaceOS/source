module PlaceOS::MQTT
  API_VERSION = "v1"
  APP_NAME    = "mqtt"
  HIERARCHY   = ENV["PLACE_MQTT_HIERARCHY"]?.try(&.split(' ')) || ["org", "building", "level", "area"]
  VERSION     = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
end
