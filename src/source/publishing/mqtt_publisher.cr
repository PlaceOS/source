require "file"
require "json"
require "mqtt/v3/client"
require "placeos-models/broker"
require "retriable"
require "rwlock"
require "tasker"

require "./publisher"

module PlaceOS::Source
  # Publish to registered MQTT Brokers
  class MqttPublisher < Publisher
    Log = ::Log.for(self)

    private struct Event
      include JSON::Serializable

      @[JSON::Field(converter: Time::EpochConverter)]
      getter time : Time
      @[JSON::Field(converter: String::RawConverter, emit_null: true)]
      getter value : String?

      def initialize(@value, @time)
      end
    end

    def self.payload(value, broker : PlaceOS::Model::Broker?, timestamp : Time = self.timestamp)
      value = broker.sanitize(value) unless broker.nil? || value.nil?
      Event.new(value, timestamp).to_json
    end

    private getter broker : PlaceOS::Model::Broker
    private getter broker_lock : RWLock = RWLock.new
    protected getter client : ::MQTT::V3::Client

    def initialize(@broker : PlaceOS::Model::Broker)
      @client = new_client
    end

    protected def new_client
      @client = MqttPublisher.client(@broker)
    end

    def stop
      super
      client.wait_close
      client.disconnect
    end

    def set_broker(broker : PlaceOS::Model::Broker)
      broker_lock.write do
        @broker = broker
      end
    end

    # Create an authenticated MQTT client off metadata in the Broker
    def self.client(broker : PlaceOS::Model::Broker)
      Log.debug { {message: "creating MQTT client", host: broker.host, port: broker.port.to_s, tls: broker.tls} }

      # Create a transport (TCP, UDP, Websocket etc)
      tls = if broker.tls
              tls_client = OpenSSL::SSL::Context::Client.new
              tls_client.verify_mode = OpenSSL::SSL::VerifyMode::NONE
              tls_client
            else
              nil
            end

      transport = ::MQTT::Transport::TCP.new(
        host: broker.host,
        port: broker.port,
        tls_context: tls
      )

      # Establish a MQTT connection
      client = ::MQTT::V3::Client.new(transport)

      keep_alive = 60

      client.connect(
        client_id: broker.id.as(String),
        keep_alive: keep_alive,
        username: broker.username,
        password: broker.password,
      )

      close_channel = Channel(Nil).new(1)

      repeating_task = Tasker.every((keep_alive // 3).seconds) do
        close_channel.close if client.closed?
      end

      # Spawn a helper fiber to cancel the repeating ping task
      spawn do
        # Block waiting for close event
        close_channel.receive?
        repeating_task.cancel
      end

      client
    end

    protected def publish(message : Message)
      if key = MqttPublisher.generate_key(message.data)
        # Sanitize the message payload according the Broker's filters
        payload = broker_lock.read do
          MqttPublisher.payload(message.payload, broker)
        end

        retain = case message.data
                 # Publish event to the 'status' topic
                 in Mappings::Metadata then false
                   # Update persistent 'metadata' topic (includes deleting)
                 in Mappings::Status then true
                 end

        Log.trace { {message: "writing to MQTT", key: key, retain: retain} }

        Retriable.retry(max_attempts: 20, on: IO::Error | MQTT::Error, on_retry: ->(e : Exception, _attempt : Int32, _elapsed : Time::Span, _next : Time::Span) {
          Log.error(exception: e) { "MQTT connection error, reconnecting..." }
          new_client
        }) do
          client.publish(topic: key, payload: payload, retain: retain)
        end
      end
    rescue e
      Log.error(exception: e) { "error while publishing Message<data=#{message.data}, key=#{key}, payload=#{message.payload}>" }
    end

    # Key generation
    ###########################################################################

    def self.generate_key(data : Mappings::Data)
      case data
      in Mappings::Metadata then MqttPublisher.generate_metadata_key(data)
      in Mappings::Status   then MqttPublisher.generate_status_key?(data)
      end
    end

    # Construct a model `metadata` key for MQTT
    #
    def self.generate_metadata_key(data : Mappings::Metadata) : String
      File.join(MQTT_NAMESPACE, data.scope, "metadata", data.model_id)
    end

    # Construct a Module `state` key for MQTT
    #
    # If a ZoneMapping is missing, the corresponding hierarchy value will be '_'
    def self.generate_status_key?(data : Mappings::Status) : String?
      # Look up zone or replace with _ if not present
      hierarchy_values = MqttPublisher.extract_zone_hierarchy(data.zone_mapping)

      # Get concrete values for scope Zones
      scope_value = hierarchy_values.first?

      # Prevent publishing events with unspecified top-level scope
      if scope_value.nil? || scope_value == "_"
        Log.debug { "#{data.status} event for #{data.module_id} ignored due to missing top-level scope" }
        return
      end

      # Construct key path dependent on Zone hierarchy
      subhierarchy = File.join(hierarchy_values[1..])

      # Construct key path dependent on Module's metadata
      module_key = File.join(
        data.control_system_id,
        data.driver_id,
        data.module_name,
        data.index.to_s,
        data.status
      )

      # Construct complete key
      File.join(
        MQTT_NAMESPACE,
        scope_value,
        "state",
        subhierarchy,
        module_key,
      )
    end

    def self.extract_zone_hierarchy(zone_mapping : Hash(String, String))
      HIERARCHY.map { |key| zone_mapping[key]? || "_" }
    end
  end
end
