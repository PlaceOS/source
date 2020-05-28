# Contributing

The design heavily relies on the `PlaceOS::Core::Resource` abstraction.

## Design

The individual components are roughly laid out below.
For more detail, see the files themselves.

- `constants.cr`
- `driver_router.cr`
  + Publishes `Driver` models to the `metadata` topic (via `PublishMetadata`)
- `manager.cr`
  + Manages the application start-up
- `status_events.cr`
  + Listens for redis events via a pattern subscription
  + Parses events, gets topic keys and writes the events to `PublisherManager`
- `module_router.cr`
  + Maintains a mapping of `module_id` to `driver_id`
- `publish_metadata.cr`
  + Module with a helper to Publish a model under the `metadata` key via `PublisherManager`
- `publisher.cr`
  + Abstraction over an MQTT client, writing to a broker specified by a `Model::Broker`
  + Sanitizes data via `Model::Broker` filters
  + Writes state events to `/<org>/state/..`
  + Writes metadata events to `/<org>/metadata/..`
- `publisher_manager.cr`
  + Handles creation of `Publisher`s
  + Broadcasts events across `Publisher`s
- `resource.cr`
  + Reexport of `PlaceOS::Core::Resource`
- `system_router.cr`
  + Publishes `ControlSystem` models to the `metadata` topic (via `PublishMetadata`)
  + Maintains `control_system_id` to `ZoneMapping` mappings. For use in generating `state` keys.
  + Maintains `module_id` to `Array(ModuleMapping)` mappings. For use in generating `state` keys.
  + Maintains `module_id` to `driver_id` mappings. For use in generating `state` keys.
- `zone_router.cr`
  + Publishes `Zone` models to the `metadata` topic (via `PublishMetadata`)
