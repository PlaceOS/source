module PlaceOS::MQTT
  APP_NAME    = "mqtt"
  API_VERSION = "v1"
  VERSION     = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
end
