## Unreleased

### Fix

- **telemetry**: ensure `Instrument` in scope
- update `placeos-log-backend`
- **telemetry**: seperate telemetry folder
- **mqtt_broker_manager**: start created publisher

### Feat

- **logging**: configure OpenTelemetry
- **logging**: set up from env
- **mqtt_broker_manager**: add logs for rw lock

### Refactor

- central build CI (#32)

## v1.5.0 (2022-01-24)

### Fix

- creating mqtt publisher blocks (#29)
- **publishing influx**: tags are required to be unique (#28)
- **influx publishing**: the system id needs to be indexed (#17)
- **publishing publisher**: handle publish exceptions
- **publishing publisher**: handle publish exceptions
- **logging**: change redis pevent log to debug
- **logging**: remove pevent payload and lower to trace
- **logging**: remove payloads from logs to reduce noise
- **Dockerfile.test**: remove shard.override.yml
- **status_events**: verbose logging
- **influx-publisher**: forward start to publisher
- dev builds

### Feat

- **influx publisher**: allow drivers to define measurement names (#27)
- **influx publisher**: adds support for nested hashes
- **influx publisher**: adds support for nest hashes
- **shard.lock**: bump deps
- add healthcheck and version
- **logging**: configure `Log.progname`
- **logstash**: add placeos-log-backend
- **influx publisher**: add support for custom metrics
- **influx_publisher.cr**: use status name as field name

### Perf

- **influx_publisher**: return earlier if no payload (#24)

## v1.2.0 (2020-09-17)

### Fix

- **router**: remove references if deleted model has no zone_mappings

## v1.1.0 (2020-09-17)

### Fix

- **mappings**: temporary fix for readers-writer deadlock on reentrant writes

### Refactor

- finish migration from mqtt name

### Feat

- **controllers:root**: add healthcheck on root

## v1.0.0 (2020-09-04)

### Feat

- InfluxDB publishing (#4)
- **manager**: add `MQTT::StausEvents` to `Manager`
- **publisher**: MQTT client from `PlaceOS::Model::Broker`
- **router:control_system**: implement handler
- **router:zone**: implement handler
- **router:module**: implement handlers
- **status_events**: parse events from redis psub and forward to brokers
- base of `DriverRouter`, handle destroyed `Zone`s correctly in `SystemRouter`
- **publisher_manager**: publisher creation/updates/removal and message broadcasts
- base `ZoneRouter` and `ModuleRouter` implementations
- zone mapping updates/generation in SystemRouter
- scaffold

### Fix

- **publisher**: add a timestamp to the mqtt payload
- **publisher**: add a timestamp to the mqtt payload
- **status_events**: broadcast to all keys generated from a status event
- **mappings**: scope topics beneath `placeos` topic
- **router:control_system**: avoid compiler bug
- **publisher_manager**: `create_publisher` if update failed

### Refactor

- remove unused CLI flags, private hierarchy_tag set
- **mappings**: single RW lock for mapping state