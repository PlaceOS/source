require "file"
require "models/broker"
require "mqtt/v3/client"
require "rwlock"

require "../constants"

module PlaceOS::MQTT
  # Publish to registered MQTT Brokers
  class Publisher
    Log = ::Log.for("mqtt.publisher")

    record Metadata, key : String, payload : String?
    record State, key : String, payload : String
    alias Message = State | Metadata

    def self.metadata(scope : String, id : String, payload : String?)
      Metadata.new(File.join(MQTT_NAMESPACE, scope, "metadata", id), payload)
    end

    def self.state(key : String, payload : String)
      State.new(key, payload)
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

    def consume_messages
      spawn do
        while message = message_queue.receive?
          publish(message)
        end
      end
    end

    protected def publish(message : Message)
      case message
      when Metadata
        # Update persistent metadata topic (includes deleting)
        client.publish(topic: message.key, payload: message.payload, retain: true)
      when State
        # Publish event to generated key
        client.publish(topic: message.key, payload: message.payload)
      end
    rescue e
      Log.error(exception: e) { "error while publishing Message<#{message.inspect}>" }
    end
  end
end
