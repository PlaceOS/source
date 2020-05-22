require "rwlock"
require "file"
require "mqtt/v3/client"

module PlaceOS::MQTT
  # Publish to registered MQTT Brokers
  class Publisher
    Log = ::Log.for("mqtt.publisher")

    record Metadata, key : String, payload : String?
    record State, key : String, payload : String
    alias Message = State | Metadata

    def self.metadata(scope : String, id : String, payload : String?)
      Metadata.new(File.join(scope, id), payload)
    end

    def self.state(key : String, payload : String)
      State.new(key, payload)
    end

    getter message_queue : Channel(Message) = Channel(Message).new

    protected getter client : ::MQTT::V3::Client

    private getter broker : Model::Broker
    private getter broker_lock : RWLock = RWLock.new

    def write_broker
      broker_lock.write do
        yield broker
      end
    end

    def read_broker
      broker_lock.read do
        yield broker
      end
    end

    def set_broker(broker : Model::Broker)
      broker_lock.write do
        @broker = broker
      end
    end

    def initialize(@broker : Model::Broker)
      @client = Publisher.client(@broker)
    end

    def close
      message_queue.close
      client.wait_close
      client.disconnect
    end

    # Create an authenticated MQTT client off metadata in the Broker
    def self.client(broker : Model::Broker)
      # Create a transport (TCP, UDP, Websocket etc)
      tls = OpenSSL::SSL::Context::Client.new
      tls.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      transport = ::MQTT::Transport::TCP.new("test.mosquitto.org", 8883, tls)

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
      when State
        # Generate key from routers and update state key
        # Publish event to generated key
      end
    rescue e
      Log.error(exception: e) { "error while publishing Message<#{message.inspect}>" }
    end
  end
end
