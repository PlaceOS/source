## v1.12.1 (2023-07-04)

### Fix

- **eventbus**: handle read replica race conditions

## v1.12.0 (2023-06-26)

### Feat

- **shard.lock**: bump opentelemetry-instrumentation.cr

## v1.11.1 (2023-03-15)

### Refactor

- migrate to postgres ([#51](https://github.com/PlaceOS/source/pull/51))

## v1.11.0 (2023-02-15)

### Feat

- **influx_publisher**: allow overriding the timestamp ([#53](https://github.com/PlaceOS/source/pull/53))

## v1.10.1 (2023-02-09)

### Fix

- **status_events**: handle errors on initial sync ([#52](https://github.com/PlaceOS/source/pull/52))

## v1.10.0 (2022-11-15)

### Feat

- **status_events**: update values on startup ([#49](https://github.com/PlaceOS/source/pull/49))

## v1.9.3 (2022-10-25)

### Fix

- **status_events**: switch to simple_retry ([#48](https://github.com/PlaceOS/source/pull/48))

## v1.9.2 (2022-10-18)

### Fix

- **publishing/influx_publisher**: use float64 for numeric field types ([#46](https://github.com/PlaceOS/source/pull/46))

## v1.9.1 (2022-09-15)

### Fix

- **mappings**: lazy load in the driver ids if they don't exist ([#44](https://github.com/PlaceOS/source/pull/44))

## v1.9.0 (2022-09-08)

### Feat

- **shard.lock**: bump libs ([#43](https://github.com/PlaceOS/source/pull/43))

## v1.8.1 (2022-09-08)

### Fix

- **Dockerfile**: revert static build ([#42](https://github.com/PlaceOS/source/pull/42))

## v1.8.0 (2022-09-07)

### Feat

- add ARM64 image support ([#41](https://github.com/PlaceOS/source/pull/41))

## v1.7.0 (2022-09-04)

### Feat

- update action controller ([#40](https://github.com/PlaceOS/source/pull/40))

## v1.6.0 (2022-05-06)

### Feat

- **logging**: configure OpenTelemetry
- **logging**: set up from env
- **mqtt_broker_manager**: add logs for rw lock

### Fix

- **telemetry**: ensure `Instrument` in scope
- update `placeos-log-backend`
- **telemetry**: seperate telemetry folder
- **mqtt_broker_manager**: start created publisher

### Refactor

- central build CI ([#32](https://github.com/PlaceOS/source/pull/32))

## v1.5.0 (2022-01-24)

### Feat

- **influx publisher**: allow drivers to define measurement names ([#27](https://github.com/PlaceOS/source/pull/27))
- **influx publisher**: adds support for nest hashes
- **shard.lock**: bump deps
- add healthcheck and version
- **logging**: configure `Log.progname`
- **logstash**: add placeos-log-backend
- **influx publisher**: add support for custom metrics
- **influx_publisher.cr**: use status name as field name

### Fix

- creating mqtt publisher blocks ([#29](https://github.com/PlaceOS/source/pull/29))
- **publishing influx**: tags are required to be unique ([#28](https://github.com/PlaceOS/source/pull/28))
- **influx publishing**: the system id needs to be indexed ([#17](https://github.com/PlaceOS/source/pull/17))
- **publishing publisher**: handle publish exceptions
- **logging**: change redis pevent log to debug
- **logging**: remove pevent payload and lower to trace
- **logging**: remove payloads from logs to reduce noise
- **Dockerfile.test**: remove shard.override.yml
- **status_events**: verbose logging
- **influx-publisher**: forward start to publisher
- dev builds

### Perf

- **influx_publisher**: return earlier if no payload ([#24](https://github.com/PlaceOS/source/pull/24))

## v1.2.0 (2020-09-17)

### Fix

- **router**: remove references if deleted model has no zone_mappings

## v1.1.0 (2020-09-17)

### Feat

- **controllers:root**: add healthcheck on root

### Fix

- **mappings**: temporary fix for readers-writer deadlock on reentrant writes

### Refactor

- finish migration from mqtt name

## v1.0.0 (2020-09-04)

### Feat

- InfluxDB publishing ([#4](https://github.com/PlaceOS/source/pull/4))
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
- **status_events**: broadcast to all keys generated from a status event
- **mappings**: scope topics beneath `placeos` topic
- **router:control_system**: avoid compiler bug
- **publisher_manager**: `create_publisher` if update failed

### Refactor

- remove unused CLI flags, private hierarchy_tag set
- **mappings**: single RW lock for mapping state
