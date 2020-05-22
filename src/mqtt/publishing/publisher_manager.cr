require "models/broker"
require "rwlock"

require "./publisher"
require "../resource"

module PlaceOS::MQTT
  # Create and maintain Publishers from Brokers
  class PublisherManager < Resource(Model::Broker)
    Log = ::Log.for("mqtt.publisher_manager")

    @@instance : PublisherManager?

    # Class to be used as a singleton
    def self.instance : PublisherManager
      (@@instance ||= PublisherManager.new).as(PublisherManager)
    end

    # Broadcast a message to each MQTT Broker
    #
    def broadcast(message : Publisher::Message)
      read_publishers do |publishers|
        publishers.values.each do |publisher|
          publisher.message_queue.send(message)
        end
      end
    end

    def process_resource(event) : Resource::Result
      model = event[:resource]

      # Don't recreat the publisher if only safe attributes changed
      case event[:action]
      when Resource::Action::Created
        create_publisher(model)
      when Resource::Action::Updated
        if PublisherManager.safe_update?(model)
          update_publisher(model)
        else
          # Recreate the publisher
          create_publisher(model)
        end
      when Resource::Action::Deleted
        remove_publisher(model)
      end.as(Resource::Result)
    end

    # Attributes that can change without recreating the publisher
    SAFE_ATTRIBUTES = [:name, :description, :filters]

    # Create a `Publisher` for the `Broker`
    #
    protected def create_publisher(broker : Model::Broker) : Resource::Result
      broker_id = broker.id.as(String)
      publisher = Publisher.new(broker)
      write_publishers do |publishers|
        # Close off exisiting publisher, if present
        existing = publishers[broker_id]?
        existing.close unless existing.nil?
        publishers[broker_id] = publisher
      end

      Resource::Result::Success
    end

    # Update safe fields on the `Publisher`'s `Broker`
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

    # Close and remove the `Publisher` for the `Broker`
    #
    private def remove_publisher(broker : Model::Broker) : Resource::Result
      broker_id = broker.id.as(String)
      existing = write_publishers do |publishers|
        publishers.delete(broker_id)
      end

      existing.close unless existing.nil?

      Resource::Result::Success
    end

    # Mapping from broker_id to an MQTT publisher
    @publishers : Hash(String, Publisher) = {} of String => Publisher

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
