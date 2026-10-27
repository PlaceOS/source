require "csv"
require "http/client"

require "../spec_helper"

# End to end: status written to Redis the way a driver writes it, carried by
# `StatusEvents` to the InfluxDB the test stack runs, and read back with Flux
module PlaceOS::Source
  # Every point written for a system, one row per point with its fields
  # pivoted into columns alongside the tags.
  #
  # NOTE:: read as plain CSV rather than with `Flux::Client#query`, which
  # cannot parse a result holding more than one schema — and points with
  # different fields and tags come back as one table schema each
  def self.influx_points(system_id : String) : Array(Hash(String, String))
    flux = <<-FLUX
      from(bucket: "#{INFLUX_BUCKET}")
        |> range(start: 0)
        |> filter(fn: (r) => r.pos_system == "#{system_id}")
        |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
      FLUX

    uri = URI.parse(INFLUX_HOST.not_nil!)
    headers = HTTP::Headers{
      "Authorization" => "Token #{INFLUX_API_KEY}",
      "Accept"        => "application/csv",
      "Content-Type"  => "application/json",
    }
    body = {query: flux, dialect: {annotations: [] of String, header: true}}.to_json
    response = HTTP::Client.new(uri).post("/api/v2/query?org=#{URI.encode_www_form(INFLUX_ORG)}", headers, body)
    raise "query failed: #{response.status_code} #{response.body}" unless response.success?

    # each table is a header row and its records, tables separated by a blank line
    response.body.split(/\r?\n\r?\n/).flat_map do |table|
      next [] of Hash(String, String) if table.strip.empty?
      rows = CSV.parse(table.strip)
      header = rows.shift
      rows.map { |row| header.zip(row).to_h.reject { |_key, value| value.empty? } }
    end
  end

  def self.eventually(timeout : Time::Span = 20.seconds, interval : Time::Span = 250.milliseconds, &)
    expire = Time.instant + timeout
    loop do
      return if yield
      raise "condition not met within #{timeout}" if Time.instant > expire
      sleep interval
    end
  end

  # A Module's status events, as published by a driver, flowing to `managers`
  class IngestPipeline
    getter module_id : String
    getter system_id : String = "cs-#{UUID.random}"
    # the measurement, unique so field types never clash with earlier runs
    getter module_name : String = "ingest_#{Random::Secure.hex(6)}"
    getter status_events : StatusEvents
    getter mappings : Mappings

    def initialize(managers : Array(PublisherManager), @module_id = "mod-#{UUID.random}")
      state = PlaceOS::Source.mock_state(
        module_id: module_id,
        module_name: module_name,
        control_system_id: system_id,
        org_id: "org-#{UUID.random}",
      )
      @mappings = Mappings.new(state)
      @status_events = StatusEvents.new(@mappings, managers)
      spawn { @status_events.start }
      PlaceOS::Source.eventually(10.seconds) { @status_events.initial_sync_complete? }
      # time for the pattern subscription to be established
      sleep 500.milliseconds
    end

    def store : PlaceOS::Driver::RedisStorage
      PlaceOS::Driver::RedisStorage.new(module_id)
    end

    def set(status : String, value) : Nil
      store[status] = value.to_json
    end

    # The MQTT topic a status is published to
    def topic(status : String) : String
      MqttPublisher.generate_key(mappings.status_events?(module_id, status).not_nil!.first).not_nil!
    end

    def points : Array(Hash(String, String))
      PlaceOS::Source.influx_points(system_id)
    end

    def stop
      status_events.stop
      store.clear rescue nil
    end
  end

  def self.influx_manager : InfluxManager
    manager = InfluxManager.new(INFLUX_HOST.not_nil!, INFLUX_API_KEY.not_nil!)
    # rather than the production interval, so specs are not waiting on it
    manager.publisher.commit_interval = 500.milliseconds
    manager
  end

  describe "InfluxDB ingest" do
    it "writes each supported payload format to InfluxDB" do
      influx = influx_manager
      influx.start
      pipeline = IngestPipeline.new([influx] of PublisherManager)

      begin
        pipeline.set "power", true
        pipeline.set "volume", 42.5
        pipeline.set "input", "hdmi"
        pipeline.set "owner", "someone@example.com"
        pipeline.set "climate", {temperature: 21.5, humidity: 40, measurement: "climate"}
        pipeline.set "rooms", {"r1" => {people: 3}, "r2" => {people: 5}}
        pipeline.set "desks", [{desk: "d1", occupied: true}, {desk: "d2", occupied: false}]
        seen = Time.utc.to_unix - 60
        pipeline.set "locations", {
          ts_hint:      "complex",
          measurement:  "locations",
          ts_map:       {x: "xloc"},
          ts_tag_keys:  ["mac"],
          ts_tags:      {pos_building: "custom-building"},
          ts_fields:    {source: "wifi"},
          ts_timestamp: "seen",
          value:        [{x: 1.5, mac: "aa", seen: seen}, {x: 2.5, mac: "bb", seen: seen + 1}],
        }
        # neither of these can be stored, so nothing is written for them
        pipeline.set "nothing", nil
        pipeline.set "control", "bad\u0001value"

        points = [] of Hash(String, String)
        eventually { (points = pipeline.points).size >= 11 }
        sleep 1.second
        points = pipeline.points

        by_key = points.group_by { |point| point["pos_key"] }
        by_key.keys.sort!.should eq %w[climate desks input locations owner power rooms volume]

        # every point carries the hierarchy and module tags
        points.each do |point|
          point["pos_module"].should eq pipeline.module_name
          point["pos_index"].should eq "1"
          point["pos_driver"].should eq "12345"
        end

        # scalars, one field named after the status
        power = by_key["power"].first
        power["_measurement"].should eq pipeline.module_name
        power["power"].should eq "true"
        power["pos_level"].should eq "nek"
        by_key["volume"].first["volume"].should eq "42.5"
        by_key["input"].first["input"].should eq "hdmi"

        # strings matching the default filters are hashed before storage
        owner = by_key["owner"].first["owner"]
        owner.should_not eq "someone@example.com"
        owner.size.should eq 64

        # a hash, one field per key, with a measurement of its own
        climate = by_key["climate"].first
        climate["_measurement"].should eq "climate"
        climate["temperature"].should eq "21.5"
        climate["humidity"].should eq "40"

        # a hash of hashes, one point per entry
        rooms = by_key["rooms"].sort_by(&.["pos_uniq"])
        rooms.map(&.["parent_hash_key"]).should eq %w[r1 r2]
        rooms.map(&.["people"]).should eq %w[3 5]

        # an array of hashes, one point per element
        desks = by_key["desks"].sort_by(&.["pos_uniq"])
        desks.map(&.["desk"]).should eq %w[d1 d2]
        desks.map(&.["occupied"]).should eq %w[true false]

        # complex: mapped field names, fields promoted to tags, tags and fields
        # added to every point, and a timestamp taken from the value
        locations = by_key["locations"].sort_by(&.["pos_uniq"])
        locations.size.should eq 2
        locations.each do |point|
          point["_measurement"].should eq "locations"
          point["pos_building"].should eq "custom-building"
          point["source"].should eq "wifi"
        end
        locations.map(&.["xloc"]).should eq %w[1.5 2.5]
        locations.map(&.["mac"]).should eq %w[aa bb]
        locations.map { |point| Time.parse_rfc3339(point["_time"]).to_unix }.should eq [seen, seen + 1]
      ensure
        pipeline.stop
        influx.stop
      end
    end

    it "writes a slow trickle of events without waiting for a full batch" do
      influx = influx_manager
      influx.start
      pipeline = IngestPipeline.new([influx] of PublisherManager)

      begin
        # an event more often than the commit interval, never enough to fill a
        # batch: the buffer is never idle for a whole interval
        spawn do
          20.times do |index|
            pipeline.set "trickle", index
            sleep 200.milliseconds
          end
        end

        eventually(3.seconds) { pipeline.points.size > 0 }
      ensure
        pipeline.stop
        influx.stop
      end
    end

    it "writes buffered points when stopped" do
      influx = influx_manager
      influx.publisher.commit_interval = 1.minute
      influx.start
      pipeline = IngestPipeline.new([influx] of PublisherManager)

      begin
        pipeline.set "power", true
        eventually { influx.publisher.processed > 0 }
        influx.stop
        eventually(5.seconds) { pipeline.points.size == 1 }
      ensure
        pipeline.stop
      end
    end

    describe "with an MQTT broker that is not working" do
      it "keeps writing to InfluxDB after the broker drops away" do
        relay = BrokerRelay.new(test_broker.host, test_broker.port)
        broker = relay.broker
        mqtt = MqttBrokerManager.new
        mqtt.process_resource(:created, broker).should eq Resource::Result::Success

        influx = influx_manager
        influx.start
        # MQTT first, as the service registers them
        pipeline = IngestPipeline.new([mqtt, influx] of PublisherManager)

        begin
          # the broker works to begin with
          subscriber = PlaceOS::Source.subscriber
          key = pipeline.topic("s_first")
          received = PlaceOS::Source.subscribe_channel(subscriber, key)
          sleep 200.milliseconds
          pipeline.set "s_first", true
          PlaceOS::Source.take(received, key)
          subscriber.disconnect rescue nil

          relay.cut

          # comfortably more than a publisher's queue holds
          count = StatusEvents::BATCH_SIZE * 3
          count.times { |index| pipeline.set "s_#{index}", index }

          eventually(20.seconds) { pipeline.points.size >= count + 1 }
          pipeline.points.size.should eq count + 1
        ensure
          pipeline.stop
          influx.stop
          relay.cut
          mqtt.process_resource(:deleted, broker) rescue nil
        end
      end

      it "writes to InfluxDB when the broker never connects" do
        relay = BrokerRelay.new(test_broker.host, test_broker.port)
        relay.cut
        broker = relay.broker
        mqtt = MqttBrokerManager.new
        mqtt.process_resource(:created, broker).should eq Resource::Result::Error

        influx = influx_manager
        influx.start
        pipeline = IngestPipeline.new([mqtt, influx] of PublisherManager)

        begin
          count = StatusEvents::BATCH_SIZE * 3
          count.times { |index| pipeline.set "s_#{index}", index }

          eventually(20.seconds) { pipeline.points.size >= count }
          pipeline.points.size.should eq count
        ensure
          pipeline.stop
          influx.stop
        end
      end
    end

    # A resync republishes the current value of every status so MQTT brokers
    # retain it. InfluxDB holds a time series: the same values again, stamped
    # now, would record changes that never happened
    it "does not write a broker resync to InfluxDB" do
      mod = Model::Generator.module.save!
      influx = influx_manager
      influx.start
      mqtt = MockManager.new
      pipeline = IngestPipeline.new([mqtt, influx] of PublisherManager, mod.id.as(String))

      begin
        pipeline.set "power", true
        eventually { pipeline.points.size == 1 }

        mqtt.messages.clear
        pipeline.status_events.resync_state

        eventually(5.seconds) { mqtt.messages.any? { |message| message.data.as?(Mappings::Status).try(&.status) == "power" } }
        sleep 1.second
        pipeline.points.size.should eq 1
      ensure
        pipeline.stop
        influx.stop
        mod.destroy
      end
    end
  end
end
