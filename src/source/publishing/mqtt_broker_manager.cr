require "placeos-models/broker"
require "placeos-resource"

require "./publisher"
require "./mqtt_publisher"

module PlaceOS::Source
  # Create and maintain Publishers from Brokers
  class MqttBrokerManager < Resource(Model::Broker)
    include PublisherManager

    Log = ::Log.for(self)

    # Callback to trigger state sync when new brokers are added
    property on_broker_ready : Proc(String, Nil)?

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

    # Broadcast a deletion to each MQTT Broker
    #
    def broadcast_delete(message : Publisher::Message)
      read_publishers do |publishers|
        publishers.values.each do |publisher|
          publisher.queue_delete(message)
        end
      end
    end

    # The publishers as they are now, one per Broker
    def publishers : Array(MqttPublisher)
      read_publishers(&.values.dup)
    end

    def deletes_pending? : Bool
      read_publishers do |publishers|
        publishers.values.any?(&.deletes_pending?)
      end
    end

    def stats : Hash(String, UInt64)
      hash = {} of String => UInt64
      read_publishers do |publishers|
        publishers.values.each do |publisher|
          hash["MQTT: #{publisher.broker.name}"] = publisher.processed
        end
      end
      hash
    end

    def process_resource(action : Resource::Action, resource : Model::Broker) : Resource::Result
      # Don't recreate the publisher if only "safe" attributes have changed
      case action
      in .created? then create_publisher(resource)
      in .updated?
        if MqttBrokerManager.safe_update?(resource)
          update_publisher(resource)
        else
          # Recreate the publisher
          create_publisher(resource)
        end
      in .deleted? then remove_publisher(resource)
      end
    end

    # Attributes that can change without recreating the publisher
    SAFE_ATTRIBUTES = [:name, :description, :filters]

    # Create a `MqttPublisher` for the `Broker`
    #
    protected def create_publisher(broker : Model::Broker, retry : Bool = true) : Resource::Result
      broker_id = broker.id.as(String)
      existing = read_publishers(&.[broker_id]?)
      existing.try &.superseded = true
      begin
        publisher = MqttPublisher.new(broker)
      rescue e
        existing.try &.superseded = false
        # NOTE:: any error, not only `IO::Error`: a refused connection surfaces
        # as `MQTT::NotConnectedError`, and an unhandled one drops the Broker
        # for good — nothing is published to it until source restarts. A broker
        # that starts after source, or restarts under it, is ordinary
        Log.error(exception: e) { "failed to connect to broker on #{broker.host}:#{broker.port}#{", retrying" if retry}" }
        retry_publisher(broker_id) if retry
        return Resource::Result::Error
      end

      already_publishing = write_publishers do |publishers|
        # Close off exisiting publisher, if present
        existing = publishers[broker_id]?
        existing.try &.superseded = true
        existing.stop unless existing.nil?
        publishers[broker_id] = publisher
        !existing.nil?
      end

      publisher.on_reconnect = -> {
        Log.info { "reconnected to Broker<#{broker_id}>, republishing state" }
        on_broker_ready.try &.call(broker_id)
        nil
      }
      publisher.start

      # Trigger state sync callback if this is a new broker after startup.
      #
      # NOTE:: "new" has to mean we had no publisher for it, not merely that
      # startup has finished. `Resource#start` opens the changefeed before it
      # loads existing rows, so a create event for a Broker we already loaded
      # arrives once startup is marked complete — and re-publishing all state
      # for a Broker we were already connected to is wasted work
      if startup_finished? && !already_publishing
        Log.info { "new broker connected after startup, triggering state sync for Broker<#{broker_id}>" }
        on_broker_ready.try &.call(broker_id)
      end

      Resource::Result::Success
    end

    private getter retrying = Set(String).new
    private getter retrying_lock = Mutex.new

    # Tries the Broker again with backoff, reading it from the database each
    # time, until a publisher for it exists or the Broker is gone
    protected def retry_publisher(broker_id : String) : Nil
      return unless retrying_lock.synchronize { retrying.add?(broker_id) }

      spawn do
        delay = 1.second
        begin
          loop do
            sleep delay
            delay = {delay * 2, 30.seconds}.min
            break if read_publishers(&.has_key?(broker_id))
            break unless broker = Model::Broker.find?(broker_id)
            break if create_publisher(broker, retry: false).success?
          end
        ensure
          retrying_lock.synchronize { retrying.delete(broker_id) }
        end
      end
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
    private def read_publishers(&)
      Log.trace { "waiting to read publishers" }
      publishers_lock.read do
        Log.trace { "reading publishers" }
        yield @publishers
      end
    end

    # Synchronized write access
    #
    private def write_publishers(&)
      Log.trace { "waiting to write publishers" }
      publishers_lock.write do
        Log.trace { "writing publishers" }
        yield @publishers
      end
    end

    # Safe to update if fields in SAFE_ATTRIBUTES changed
    #
    def self.safe_update?(model : Model::Broker)
      # Take the union of the changed fields and the safe fields
      attribute_union = model.changed_attributes.keys | SAFE_ATTRIBUTES
      # Union should be the same size iff fields are in SAFE_ATTRIBUTES
      attribute_union.size == SAFE_ATTRIBUTES.size
    end
  end
end
