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

    # NOTE:: the event only says which Broker changed. What is applied is the
    # Broker as it is in the database now, one change per Broker at a time.
    # Events are processed concurrently, so two edits made close together
    # could otherwise finish out of order, and the older one win
    def process_resource(action : Resource::Action, resource : Model::Broker) : Resource::Result
      broker_id = resource.id.as(String)
      broker = action.deleted? ? nil : current_broker(resource)
      apply(broker_id, broker)
    end

    # The Broker's row in the database, or `nil` once it is gone
    #
    # A Broker that was never saved has no row to read, so it is taken as is
    private def current_broker(resource : Model::Broker) : Model::Broker?
      return resource if resource.new_record?
      Model::Broker.find?(resource.id.as(String))
    rescue e
      Log.warn(exception: e) { "could not read Broker<#{resource.id}>, applying the change as received" }
      resource
    end

    # Brings the publisher for a Broker in line with it: created, replaced,
    # updated in place or removed
    protected def apply(broker_id : String, broker : Model::Broker?, retry : Bool = true) : Resource::Result
      broker_lock(broker_id).synchronize do
        return remove_publisher(broker_id) if broker.nil?

        existing = read_publishers(&.[broker_id]?)
        if existing.nil?
          create_publisher(broker, retry: retry, resync: startup_finished?)
        elsif MqttBrokerManager.same_connection?(existing.broker, broker)
          existing.set_broker(broker)
          Resource::Result::Success
        else
          # NOTE:: a new connection may be to a different broker altogether,
          # one that holds none of our state, so publish all of it again
          create_publisher(broker, retry: retry, resync: true)
        end
      end
    end

    # Whether both connect the same way. A change to anything else is applied
    # to the running publisher, without reconnecting
    def self.same_connection?(current : Model::Broker, updated : Model::Broker) : Bool
      current.host == updated.host &&
        current.port == updated.port &&
        current.tls == updated.tls &&
        current.auth_type == updated.auth_type &&
        current.username == updated.username &&
        current.password == updated.password &&
        current.certificate == updated.certificate
    end

    private getter broker_locks = Hash(String, Mutex).new
    private getter broker_locks_lock = Mutex.new

    private def broker_lock(broker_id : String) : Mutex
      broker_locks_lock.synchronize do
        broker_locks[broker_id] ||= Mutex.new
      end
    end

    # Create a `MqttPublisher` for the `Broker`, replacing any there is
    #
    # The existing publisher keeps running until its replacement has connected,
    # so a Broker updated with settings that do not work yet stays connected
    # with the ones that did
    private def create_publisher(broker : Model::Broker, retry : Bool, resync : Bool) : Resource::Result
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

      write_publishers do |publishers|
        # Close off exisiting publisher, if present
        existing = publishers[broker_id]?
        existing.try &.superseded = true
        existing.stop unless existing.nil?
        publishers[broker_id] = publisher
      end

      publisher.on_reconnect = -> {
        Log.info { "reconnected to Broker<#{broker_id}>, republishing state" }
        on_broker_ready.try &.call(broker_id)
        nil
      }
      publisher.start

      # NOTE:: not for the Brokers loaded at startup, the initial sync covers
      # them. `Resource#start` opens the changefeed before it loads existing
      # rows, so a create event for one of those can arrive once startup is
      # marked complete, but it finds a publisher with the same connection
      # and goes no further
      if resync
        Log.info { "connected to Broker<#{broker_id}>, triggering state sync" }
        on_broker_ready.try &.call(broker_id)
      end

      Resource::Result::Success
    end

    private getter retrying = Set(String).new
    private getter retrying_lock = Mutex.new

    # Tries the Broker again with backoff, reading it from the database each
    # time, until a publisher is connected with its current settings or the
    # Broker is gone
    #
    # NOTE:: a publisher existing is not enough. When an update fails to
    # connect, the publisher it was replacing carries on with the old settings
    protected def retry_publisher(broker_id : String) : Nil
      return unless retrying_lock.synchronize { retrying.add?(broker_id) }

      spawn do
        delay = 1.second
        begin
          loop do
            sleep delay
            delay = {delay * 2, 30.seconds}.min
            break unless broker = Model::Broker.find?(broker_id)
            current = read_publishers(&.[broker_id]?)
            break if current && MqttBrokerManager.same_connection?(current.broker, broker)
            break unless apply(broker_id, broker, retry: false).error?
          end
        rescue e
          Log.error(exception: e) { "stopped retrying Broker<#{broker_id}>" }
        ensure
          retrying_lock.synchronize { retrying.delete(broker_id) }
        end
      end
    end

    # Close and remove the `MqttPublisher` for the `Broker`
    #
    private def remove_publisher(broker_id : String) : Resource::Result
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
  end
end
