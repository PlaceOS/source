require "placeos-models/broker"
require "placeos-resource"

require "./publisher"
require "./mqtt_publisher"

module PlaceOS::Source
  # Create and maintain Publishers from Brokers
  class MqttBrokerManager < Resource(Model::Broker)
    include PublisherManager

    Log = ::Log.for(self)

    class_getter instance : self { new }

    # Broadcast a message to each MQTT Broker
    #
    def broadcast(message : Publisher::Message)
      read_publishers do |publishers|
        publishers.values.each do |publisher|
          publisher.message_queue.send(message)
        end
      end
    end

    def process_resource(action : Resource::Action, resource : Model::Broker) : Resource::Result
      # Don't recreate the publisher if only "safe" attributes have changed
      case action
      in .created?
        create_publisher(resource)
      in .updated?
        if MqttBrokerManager.safe_update?(resource)
          update_publisher(resource)
        else
          # Recreate the publisher
          create_publisher(resource)
        end
      in .deleted?
        remove_publisher(resource)
      end
    end

    # Attributes that can change without recreating the publisher
    SAFE_ATTRIBUTES = [:name, :description, :filters]

    # Create a `MqttPublisher` for the `Broker`
    #
    protected def create_publisher(broker : Model::Broker) : Resource::Result
      broker_id = broker.id.as(String)
      publisher = MqttPublisher.new(broker)
      write_publishers do |publishers|
        # Close off exisiting publisher, if present
        existing = publishers[broker_id]?
        existing.stop unless existing.nil?
        publishers[broker_id] = publisher
      end

      Resource::Result::Success
    end

    # Update safe fields on the `MqttPublisher`'s `Broker`
    #
    protected def update_publisher(broker : Model::Broker) : Resource::Result
      broker_id = broker.id.as(String)

      success = write_publishers do |publishers|
        publisher = publishers[broker_id]?
        if publisher
          publisher.set_broker(broker)
          true
        else
          Log.error { "missing existing publisher for Broker<#{broker_id}>" }
          false
        end
      end

      # Create the publisher if the update failed
      success ? Resource::Result::Success : create_publisher(broker)
    end

    # Close and remove the `MqttPublisher` for the `Broker`
    #
    private def remove_publisher(broker : Model::Broker) : Resource::Result
      broker_id = broker.id.as(String)
      existing = write_publishers do |publishers|
        publishers.delete(broker_id)
      end

      existing.stop unless existing.nil?

      Resource::Result::Success
    end

    # Mapping from broker_id to an MQTT publisher
    @publishers : Hash(String, MqttPublisher) = {} of String => MqttPublisher

    private getter publishers_lock : RWLock = RWLock.new

    # Synchronized read access
    #
    private def read_publishers
      publishers_lock.read do
        yield @publishers
      end
    end

    # Synchronized write access
    #
    private def write_publishers
      publishers_lock.write do
        yield @publishers
      end
    end

    # Safe to update iff fields in SAFE_ATTRIBUTES changed
    #
    def self.safe_update?(model : Model::Broker)
      # Take the union of the changed fields and the safe fields
      attribute_union = model.changed_attributes.keys | SAFE_ATTRIBUTES
      # Union should be the same size iff fields are in SAFE_ATTRIBUTES
      attribute_union.size == SAFE_ATTRIBUTES.size
    end
  end
end
