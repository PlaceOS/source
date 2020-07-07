require "file"
require "json"
require "mqtt/v3/client"
require "placeos-models/broker"
require "rwlock"

require "../constants"

module PlaceOS::MQTT
  # Publish to registered MQTT Brokers
  class Publisher
    Log = ::Log.for(self)

    record Metadata, key : String, payload : String do
      def initialize(@key : String, payload : String?)
        @payload = Publisher.payload(payload)
      end
    end

    record State, key : String, payload : String do
      def initialize(@key : String, payload : String)
        @payload = Publisher.payload(payload)
      end
    end

    alias Message = State | Metadata

    def self.metadata(scope : String, id : String, payload : String?)
      Metadata.new(File.join(MQTT_NAMESPACE, scope, "metadata", id), payload)
    end

    def self.state(key : String, payload : String)
      State.new(key, payload)
    end

    private struct Event
      include JSON::Serializable

      @[JSON::Field(converter: Time::EpochConverter)]
      getter time : Time
      @[JSON::Field(converter: String::RawConverter, emit_null: true)]
      getter value : String?

      def initialize(@value, @time)
      end
    end

    def self.payload(value, timestamp : Time = self.timestamp)
      Event.new(value, timestamp).to_json
    end

    def self.timestamp
      Time.utc
    end

    getter message_queue : Channel(Message) = Channel(Message).new

    protected getter client : ::MQTT::V3::Client

    private getter broker : PlaceOS::Model::Broker
    private getter broker_lock : RWLock = RWLock.new

    def set_broker(broker : PlaceOS::Model::Broker)
      broker_lock.write do
        @broker = broker
      end
    end

    def initialize(@broker : PlaceOS::Model::Broker)
      @client = Publisher.client(@broker)
      consume_messages
    end

    def close
      message_queue.close
      client.wait_close
      client.disconnect
    end

    # Create an authenticated MQTT client off metadata in the Broker
    def self.client(broker : PlaceOS::Model::Broker)
      # Create a transport (TCP, UDP, Websocket etc)
      tls = if broker.tls
              tls_client = OpenSSL::SSL::Context::Client.new
              tls_client.verify_mode = OpenSSL::SSL::VerifyMode::NONE
              tls_client
            else
              nil
            end

      transport = ::MQTT::Transport::TCP.new(broker.host.as(String), broker.port.as(Int32), tls)

      # Establish a MQTT connection
      client = ::MQTT::V3::Client.new(transport)
      client.connect

      client
    end

    private def consume_messages
      spawn do
        while message = message_queue.receive?
          publish(message)
        end
      end
    end

    protected def publish(message : Message)
      # Sanitize the payload according the Broker's filters
      payload = broker_lock.read do
        message.payload.try { |p| broker.sanitize(p) }
      end

      case message
      when Metadata
        # Update persistent metadata topic (includes deleting)
        client.publish(topic: message.key, payload: payload, retain: true)
      when State
        # Publish event to generated key
        client.publish(topic: message.key, payload: payload)
      end
    rescue e
      Log.error(exception: e) { "error while publishing Message<key=#{message.key}, payload=#{message.payload}>" }
    end
  end
end
