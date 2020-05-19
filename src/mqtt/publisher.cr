require "mqtt/v3/client"

module PlaceOS::MQTT
  # Publish to registered MQTT Brokers
  class Publisher
    Log = ::Log.for("mqtt.publisher")

    record Metadata, scope : String, id : String, payload : String?
    record State, key : String, payload : String

    alias Message = State | Metadata

    getter message_queue : Channel(Message) = Channel(Message).new

    protected getter client : MQTT::V3::Client

    def initialize(broker : Model::Broker)
    end

    # Create an authenticated MQTT client off metadata in the Broker
    def self.client(broker : Model::Broker)
      # Create a transport (TCP, UDP, Websocket etc)
      tls = OpenSSL::SSL::Context::Client.new
      tls.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      transport = MQTT::Transport::TCP.new("test.mosquitto.org", 8883, tls)

      # Establish a MQTT connection
      client = MQTT::V3::Client.new(transport)
      client.connect
    end

    def consume_messages
      spawn do
        while message = message_queue.receive?
          publish(message)
        end
      end
    end

    def publish_metadata(scope : String, id : String, payload : String?)
      message_queue.send(Metadata.new(scope, id, payload))
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
