# PlaceOS State Source Service

[![Build](https://github.com/PlaceOS/source/actions/workflows/build.yml/badge.svg)](https://github.com/PlaceOS/source/actions/workflows/build.yml)
[![CI](https://github.com/PlaceOS/source/actions/workflows/ci.yml/badge.svg)](https://github.com/PlaceOS/source/actions/workflows/ci.yml)

Service that publishes PlaceOS module state.

Currently MQTT and InfluxDB are supported backends.

## Implementation

Arbitrary hierarchies can be defined via the `PLACE_HIERARCHY` environment variable in a comma seperated list, which defaults to `org,building,level,area`.
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

## InfluxDB

`source` can optionally write status events to InfluxDB.
To configure `source` as an InfluxDB writer, set the following...
- `INFLUX_HOST`: required.
- `INFLUX_API_KEY`: required.
- `INFLUX_ORG`: defaults to `"placeos"`
- `INFLUX_BUCKET`: defaults to `"place"`

Note: The InfluxDB writer obeys the default Zone hierarchy of `org,building,level,area`


### Customising writes to InfluxDB

By default module status of compatible types (String, Float, Integer, Boolean) is written to influx in the following way:

```
# measurement,tags fields time
ModName,pos_building=zone_id,pos_level=zone_id,pos_system=sys_id,pos_module=ModName,pos_index=1 pos_driver=module_id,pos_key=status_name,status_name=status_value time_stamp
```

However where data is stored in arrays or hashes, a single status update can trigger multiple writes:

#### Arrays

```yaml
status_name: [
  {
    "measurement": "custom_measurement_name",
    "temperature": 27.8,
    "humidity": 43.2,
  },
  {
    "measurement": "custom_measurement_name",
    "temperature": 29.1,
    "humidity": 30.0,
  }
]
```

will be recorded as

```
custom_measurement_name,pos_building=zone_id,pos_level=zone_id,pos_system=sys_id,pos_module=ModName,pos_index=1,pos_uniq=0 pos_driver=module_id,pos_key=status_name,temperature=27.8,humidity=43.2 time_stamp

custom_measurement_name,pos_building=zone_id,pos_level=zone_id,pos_system=sys_id,pos_module=ModName,pos_index=1,pos_uniq=1 pos_driver=module_id,pos_key=status_name,temperature=29.1,humidity=30.0 time_stamp
```

#### Hashes

There are two styles of hashes supported

```yaml
status_name: {
  "measurement": "custom_measurement_name",
  "temperature": 27.8,
  "humidity": 43.2,
}
```

```
custom_measurement_name,pos_building=zone_id,pos_level=zone_id,pos_system=sys_id,pos_module=ModName,pos_index=1 pos_driver=module_id,pos_key=status_name,temperature=27.8,humidity=43.2 time_stamp
```

and deeper hashes

```yaml
status_name: {
  "subkey_1": {
    "measurement": "custom_measurement_name",
    "temperature": 27.8,
    "humidity": 43.2,
  },
  "subkey_2": {
    "measurement": "custom_measurement_name",
    "temperature": 29.1,
    "humidity": 30.0,
  }
}
```

```
custom_measurement_name,pos_building=zone_id,pos_level=zone_id,pos_system=sys_id,pos_module=ModName,pos_index=1,pos_uniq=0 pos_driver=module_id,pos_key=status_name,parent_hash_key=subkey_1,temperature=27.8,humidity=43.2 time_stamp

custom_measurement_name,pos_building=zone_id,pos_level=zone_id,pos_system=sys_id,pos_module=ModName,pos_index=1,pos_uniq=1 pos_driver=module_id,pos_key=status_name,parent_hash_key=subkey_2,temperature=29.1,humidity=30.0 time_stamp
```

#### Complex points

These are an array of hashes, where tags can be injected based on field names.
As well as adding additional tags and fields to each measurement.

```yaml
status_name: {
  "value": [
    {
      "temp": 27.8,
      "humidity": 43.2,
      "s2_cell_id": "88f5a11b18e4"
    },
    {
      # you can override the default metadata measurement in individual entries
      "measurement": "custom_measurement_name",
      "temp": 29.1,
      "humidity": 30.0,
      "s2_cell_id": "88f5a11b18e4"
    }
  ],

  # metadata for the data in the value array
  "measurement": "custom_measurement_name",
  "ts_hint": "complex",

  # we want to change the key name temp to temperature when we record the values
  "ts_map": {
    "temp": "temperature",
  },

  # we want the following keys to be recorded as tags
  "ts_tag_keys": [
    "s2_cell_id"
  ],

  # Add these tags to each measurement
  "ts_tags": {
    "pos_building": "zone_1",
    "pos_level": "zone_2"
  }

  # Add these fields to each measurement
  "ts_fields": {
    "additional": "data",
  }
}
```

Writes the following points to influxdb

```
custom_measurement_name,pos_building=zone_1,pos_level=zone_2,pos_system=sys_id,pos_module=ModName,pos_index=1,pos_uniq=0,s2_cell_id=88f5a11b18e4 pos_driver=module_id,pos_key=status_name,temperature=27.8,humidity=43.2,additional=data time_stamp

custom_measurement_name,pos_building=zone_1,pos_level=zone_2,pos_system=sys_id,pos_module=ModName,pos_index=1,pos_uniq=1,s2_cell_id=88f5a11b18e4 pos_driver=module_id,pos_key=status_name,temperature=29.1,humidity=30.0,additional=data time_stamp
```


## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
