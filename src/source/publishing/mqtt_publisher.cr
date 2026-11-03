require "file"
require "json"
require "mqtt/client"
require "placeos-models/broker"
require "retriable"
require "rwlock"

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

    def self.payload(value, broker : PlaceOS::Model::Broker?, timestamp : Time)
      Event.new(sanitize(value, broker), timestamp).to_json
    end

    def self.sanitize(value : String?, broker : PlaceOS::Model::Broker?) : String?
      return value if broker.nil? || value.nil?
      broker.sanitize(value)
    end

    getter broker : PlaceOS::Model::Broker
    private getter broker_lock : RWLock = RWLock.new

    # NOTE:: `MQTT::Client` negotiates the protocol version, connecting as 5.0
    # and falling back to 3.1.1 when the broker will not take it
    getter client : ::MQTT::Client

    # Called once the client has re-established a dropped connection
    property on_reconnect : Proc(Nil)? = nil

    @stopping = false

    # Set while a publisher replacing this one connects. Both use the broker id
    # as the client id, so the broker hands the session over and ends ours
    property? superseded : Bool = false

    def initialize(@broker : PlaceOS::Model::Broker)
      @client = MqttPublisher.client(@broker)

      # NOTE:: a broker that restarts without persistence comes back empty, and
      # one that was down missed whatever changed meanwhile. Either way what it
      # retains is no longer the state of the system, so a reconnection has to
      # be followed by publishing all of it again. The client calls this once
      # the broker has accepted the new connection, and from its own fiber
      @client.on_reconnect { |_session_present| on_reconnect.try &.call }

      spawn { watch_connection }
    end

    # The client reconnects by itself, and only stops for good when the broker
    # says not to come back: credentials it refuses, or another client taking
    # over our client id. Nothing is published to it after that, so say so
    private def watch_connection : Nil
      client.wait_close
      return if @stopping || superseded?
      Log.error { "MQTT client for Broker<#{broker.id}> on #{broker.host}:#{broker.port} has stopped and will not reconnect" }
    end

    # The protocol version that was actually negotiated with this broker
    def protocol_version : ::MQTT::Version?
      client.version
    end

    def stop
      @stopping = true
      super
      # NOTE:: disconnect first. `wait_close` blocks until the connection has
      # terminated, so waiting before asking it to stop hangs until the broker
      # gives up on us
      client.disconnect
      client.wait_close
    end

    def set_broker(broker : PlaceOS::Model::Broker)
      broker_lock.write do
        @broker = broker
      end
    end

    KEEP_ALIVE = 60

    # Create an authenticated MQTT client off metadata in the Broker.
    #
    # The connection settings are captured here rather than read from the model
    # on each attempt: a `Broker` update that changes them is not a "safe"
    # update, so `MqttBrokerManager` replaces the publisher outright
    def self.client(broker : PlaceOS::Model::Broker) : ::MQTT::Client
      Log.debug { {message: "creating MQTT client", host: broker.host, port: broker.port.to_s, tls: broker.tls} }

      host = broker.host
      port = broker.port
      secure = broker.tls

      # NOTE:: a factory rather than a single transport, because a socket cannot
      # be reopened. This is what lets the client re-establish the connection
      # itself, and what version negotiation needs for its fallback attempt
      client = ::MQTT::Client.new(reconnect: ::MQTT::Reconnect.new) do
        tls = if secure
                tls_client = OpenSSL::SSL::Context::Client.new
                tls_client.verify_mode = OpenSSL::SSL::VerifyMode::NONE
                tls_client
              end

        ::MQTT::Transport::TCP.new(host: host, port: port, tls_context: tls).as(::MQTT::Transport)
      end

      version = client.connect(
        client_id: broker.id.as(String),
        keep_alive: KEEP_ALIVE,
        username: broker.username,
        password: broker.password,
      )

      Log.info { {message: "connected to MQTT broker", host: host, port: port.to_s, protocol: version.to_s} }

      client
    end

    protected def publish(message : Message)
      # A status the driver cleared, or a model that was destroyed, is gone:
      # remove it rather than retain a `null` in its place. The store has no
      # value for it, so a retained `{"value": null}` would disagree with it
      if MqttPublisher.removal?(message.payload)
        return delete(message)
      end

      if key = MqttPublisher.generate_key(message.data)
        # Sanitize the message payload according the Broker's filters
        value = broker_lock.read do
          MqttPublisher.sanitize(message.payload, broker)
        end
        payload = Event.new(value, message.timestamp).to_json

        Log.trace { {message: "writing to MQTT", key: key} }

        # NOTE:: `retain: true` is what makes the current value of every status
        # available to a subscriber that connects later. The broker holds one
        # message per topic, so this is the state of the system, not a log of it
        return unless retain(key, payload)

        # A boolean status is also retained under `<key>/true` or `<key>/false`,
        # so a consumer can subscribe to, say, every `connected/false`. The
        # opposite topic is removed first, so only one of the two is ever held.
        #
        # NOTE:: decided on the sanitized value, so a Broker that filters the
        # value out does not have it given away by the topic instead
        flag = MqttPublisher.bool_topic_value(value)
        if message.data.is_a?(Mappings::Status) && !flag.nil?
          return unless retain(MqttPublisher.bool_topic(key, !flag), "")
          retain(MqttPublisher.bool_topic(key, flag), payload)
        end
      end
    rescue e
      Log.error(exception: e) { "error while publishing Message<data=#{message.data}, key=#{key}, payload=#{message.payload}>" }
    end

    # Retains `payload` under `topic`, an empty payload removing it. Returns
    # `false` when the client is not connected and nothing was written.
    #
    # The client re-establishes a dropped connection itself, so a retry here
    # only has to cover the window while that is happening. It must not build a
    # new client — the old code did, which orphaned the previous connection on
    # every retry
    private def retain(topic : String, payload : String) : Bool
      Retriable.retry(
        max_attempts: 10,
        base_interval: 250.milliseconds,
        max_interval: 5.seconds,
        on: IO::Error | MQTT::Error,
        on_retry: ->(e : Exception, _attempt : Int32, _elapsed : Time::Span, _next : Time::Span) {
          Log.warn(exception: e) { "MQTT #{payload.empty? ? "delete" : "publish"} failed, waiting for the client to reconnect" }
        }
      ) do
        # NOTE:: `closed?` holds until the broker has accepted a connection,
        # not only while the socket is down: publishing ahead of that is a
        # protocol error to a broker still taking an old session over.
        #
        # Nothing waits on a broker that is down. Retrying every
        # message until it returned held this queue for half a minute each,
        # which filled it and blocked `broadcast` — and with it every other
        # sink, InfluxDB included. Reconnecting republishes all state
        # (`on_reconnect`), and the sweep that follows removes what is stale,
        # which covers whatever is skipped here
        return false if client.closed?
        client.publish(topic: topic, payload: payload, retain: true)
      end
      true
    end

    # MQTT-3.3.1-7, a zero length retained payload removes what the broker holds
    # for the topic. Anything else — including a JSON null — would simply be
    # retained in its place, and consumers would keep seeing a value
    #
    # The value it had is not known, so both of a status' boolean topics go too
    def delete(message : Message) : Nil
      key = MqttPublisher.generate_key(message.data)
      return unless key
      delete_topic(key)
      if message.data.is_a?(Mappings::Status)
        delete_topic(MqttPublisher.bool_topic(key, true))
        delete_topic(MqttPublisher.bool_topic(key, false))
      end
    end

    # Whether a payload means the value no longer exists. Redis storage
    # publishes `"null"` when a status is deleted or the store is cleared
    def self.removal?(payload : String?) : Bool
      payload.nil? || payload == "null"
    end

    def delete_topic(key : String) : Nil
      Log.trace { {message: "removing retained value", key: key} }
      retain(key, "")
    rescue e
      Log.error(exception: e) { "error removing retained value for #{key}" }
    end

    # The status topics the broker currently retains, as a client connecting
    # now would be handed them, that `keep` returns true for. Each topic is
    # passed to `keep` as it arrives, so only those wanted are held.
    def retained_state_topics(quiet : Time::Span = 2.seconds, limit : Time::Span = 2.minutes, &keep : String -> Bool) : Set(String)
      retained_topics(File.join(MQTT_NAMESPACE, "+", "state", "#"), quiet, limit, &keep)
    end

    # The topics under `filter` the broker currently retains, that `keep`
    # returns true for, up to `max` of them.
    #
    # The broker sends retained messages straight after it acknowledges the
    # subscription, so collection ends once `quiet` passes without one, at
    # `limit`, or once `max` are held. Only retained messages count: a live
    # publication arriving meanwhile is not part of what was there.
    #
    # NOTE:: the broker drops what a client's outgoing queue cannot hold
    # (`max_queued_messages`), so on a large broker this can be part of what is
    # retained. Repeat it to see the rest once those found are dealt with
    def retained_topics(
      filter : String,
      quiet : Time::Span = 2.seconds,
      limit : Time::Span = 2.minutes,
      max : Int32 = Int32::MAX,
      &keep : String -> Bool
    ) : Set(String)
      topics = Set(String).new
      lock = Mutex.new
      last = Time.instant

      client.subscribe(filter) do |topic, payload, retained|
        next if !retained || payload.empty?
        wanted = keep.call(topic)
        lock.synchronize do
          topics << topic if wanted && topics.size < max
          last = Time.instant
        end
      end

      begin
        started = last = Time.instant
        loop do
          sleep 100.milliseconds
          now = Time.instant
          break if lock.synchronize { now - last >= quiet || topics.size >= max } || now - started >= limit
        end
      ensure
        client.unsubscribe(filter) rescue nil
      end

      lock.synchronize { topics.dup }
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

    # Where the system id sits in a state topic: after the namespace, the
    # scope, `state` and the rest of the hierarchy
    STATE_TOPIC_SYSTEM_SEGMENT = MQTT_NAMESPACE.split('/').size + 2 + (HIERARCHY.size - 1)

    # The system a state topic belongs to
    def self.state_topic_system_id(topic : String) : String?
      topic.split('/')[STATE_TOPIC_SYSTEM_SEGMENT]?
    end

    # Boolean topics
    ###########################################################################

    # Where a boolean status is also retained, `<key>/true` or `<key>/false`
    def self.bool_topic(key : String, value : Bool) : String
      "#{key}/#{value}"
    end

    # The boolean a status value is, or `nil` for any other value
    def self.bool_topic_value(value : String?) : Bool?
      case value.try &.strip
      when "true"  then true
      when "false" then false
      end
    end

    # The status key a boolean topic belongs to, or `nil` when `topic` is not
    # one. Only the shape is checked, the caller decides whether `key` is real
    def self.bool_topic_key(topic : String) : String?
      {"/true", "/false"}.each do |suffix|
        return topic.rchop(suffix) if topic.ends_with?(suffix)
      end
    end

    def self.extract_zone_hierarchy(zone_mapping : Hash(String, String))
      HIERARCHY.map { |key| zone_mapping[key]? || "_" }
    end
  end
end
