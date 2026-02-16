## v1.18.0 (2026-02-16)

### Feat

- Improve memory usage ([#63](https://github.com/PlaceOS/source/pull/63))

## v1.17.2 (2025-12-03)

### Fix

- retain all mqtt messages

## v1.17.1 (2025-11-25)

### Refactor

- [PPT-2296] Source should sync state when new brokers are added ([#62](https://github.com/PlaceOS/source/pull/62))

## v1.17.0 (2025-11-06)

### Feat

- add week_of_year, month_of_year and year fields

## v1.16.1 (2025-11-05)

### Fix

- influx does support string field values

## v1.16.0 (2025-11-05)

### Feat

- ignore string payloads and add region timezones

## v1.15.0 (2025-11-05)

### Feat

- add day of week and time of day to points [PPT-2279] ([#60](https://github.com/PlaceOS/source/pull/60))

## v1.14.0 (2025-10-30)

### Feat

- improve status publishing

## v1.13.1 (2025-10-09)

### Refactor

-  root GET endpoint to return services status + error details ([#59](https://github.com/PlaceOS/source/pull/59))

## v1.13.0 (2025-09-30)

### Feat

- [PPT-2230] Added influx health check ([#58](https://github.com/PlaceOS/source/pull/58))

## v1.12.9 (2025-08-04)

### Refactor

- App on startup to conditionally start mqtt publisher ([#57](https://github.com/PlaceOS/source/pull/57))

## v1.12.8 (2024-08-27)

### Fix

- PPT-1503 refactor event processing logic to avoid memory leak ([#55](https://github.com/PlaceOS/source/pull/55))

## v1.12.7 (2024-07-11)

### Fix

- **status_events**: parsing of initial state

## v1.12.6 (2023-10-11)

### Fix

- **root**: pg healthcheck with aurora db

## v1.12.5 (2023-07-24)

### Fix

- **status_events**: update to a lazy model loading method

## v1.12.4 (2023-07-14)

### Fix

- **resource**: replaced change feed iterator with async closure

## v1.12.3 (2023-07-14)

### Fix

- **resource**: missing change events

## v1.12.2 (2023-07-04)

### Fix

- **eventbus**: handle read replica race conditions

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
