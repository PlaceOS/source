# PlaceOS State Source Service

Service that publishes module state.

Currently MQTT and InfluxDB are supported backends.

[![Build Status](https://travis-ci.com/PlaceOS/mqtt.svg?token=tDypQH5g9ptvYso68jVV&branch=master)](https://travis-ci.com/PlaceOS/mqtt)

## Implementation

Arbitrary hierarchies can be defined via the `PLACE_MQTT_HIERARCHY` environment variable in a comma seperated list, which defaults to `org,building,level,area`.
This list defines the tags that can be applied to a `Zone` that act as scopes for events published to MQTT brokers.

### Brokers

`Broker`s are definitions of cloud/local MQTT brokers. This metadata is then used to create clients for these brokers, to which module state events and metadata events are published.

### Metadata

`ControlSystem` | `Zone` | `Driver` models are published to a persisted topic on service start and on any model changes.
Model data is only published if the model exists beneath a top-level scope `Zone`.

Metadata topic keys have the following format..
`placeos/<top-level-scope>/metadata/<model-id>`.

### State

`Module` status data is only published if the model exists beneath a top-level scope `Zone`.
`Module` status events are propagated from the running `Module` via `redis` to registered MQTT brokers.

State topic keys have the following format...
`placeos/<scope zone>/state/<2nd zone_id>/../<nth zone_id>/<system_id>/<driver_id>/<module_name>/<index>/<status>`

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
