require "./spec_helper"
require "action-controller/spec_helper"
require "placeos-driver/storage"

module PlaceOS::Source
  # A publisher whose removals can be watched, or made to never reach the
  # broker, as an ACL refusing them would
  class ControlledPublisher < MqttPublisher
    property on_delete : Proc(String, Nil)? = nil
    property? drop_deletes : Bool = false

    def delete_topic(key : String) : Nil
      super unless drop_deletes?
      on_delete.try &.call(key)
    end
  end

  # An `MqttBrokerManager` holding only the given publisher, so nothing else in
  # the database becomes a broker for the example
  def self.manager_for(publisher : MqttPublisher) : MqttBrokerManager
    manager = MqttBrokerManager.new
    manager.@publishers[publisher.broker.id.as(String)] = publisher
    manager
  end

  def self.wait_for(what : String, timeout : Time::Span = 30.seconds, &) : Nil
    expire = Time.instant + timeout
    until yield
      raise "timed out waiting for #{what}" if Time.instant > expire
      sleep 50.milliseconds
    end
  end

  # The payload a broker retains under each topic below `filter`
  def self.retained_payloads(client : ::MQTT::Client, filter : String, quiet : Time::Span = 1.second) : Hash(String, String)
    payloads = {} of String => String
    lock = Mutex.new
    last = Time.instant
    client.subscribe(filter) do |topic, payload, retained|
      next if !retained || payload.empty?
      lock.synchronize do
        payloads[topic] = String.new(payload)
        last = Time.instant
      end
      nil
    end
    until lock.synchronize { Time.instant - last >= quiet }
      sleep 100.milliseconds
    end
    client.unsubscribe(filter)
    lock.synchronize { payloads.dup }
  end

  describe "resync with clear" do
    it "leaves only what is in the database retained" do
      org = "org-#{UUID.random}"
      driver = Model::Generator.driver(role: Model::Driver::Role::Device, module_name: "Display").save!
      mod = Model::Generator.module(driver).save!
      module_id = mod.id.as(String)
      zone = Model::Generator.zone
      zone.tags = Set{Mappings.scope}
      zone.save!

      store = PlaceOS::Driver::RedisStorage.new(module_id)
      store.clear
      store["power"] = "true"

      mappings = Mappings.new(mock_state(module_id: module_id, driver_id: driver.id.as(String), org_id: org))
      live = MqttPublisher.generate_key(mappings.status_events?(module_id, "power").not_nil!.first).not_nil!

      # left behind by a Module and a Zone that were deleted
      stale_state = "placeos/#{org}/state/b/l/a/cs-gone/driver-gone/Display/1/power"
      stale_metadata = "placeos/#{Mappings.scope}/metadata/zone-gone-#{UUID.random}"

      client = subscriber
      {stale_state, stale_metadata}.each { |topic| client.publish(topic, %({"value":true}), retain: true) }

      with_publisher do |publisher|
        publisher.start
        manager = Manager.new([manager_for(publisher)] of PublisherManager, mappings)
        spawn { manager.status_events.start }
        wait_for("the initial sync") { manager.status_events.initial_sync_complete? }

        manager.resync(clear: true).should be_true
        wait_for("the resync") { !manager.resync_status.running? }

        status = manager.resync_status
        status.state.complete?.should be_true
        status.clear?.should be_true
        status.cleared.should be >= 2
        status.metadata.should be >= 1
        status.finished_at.should_not be_nil

        # republishing is queued, so give it a moment to reach the broker
        wait_for("the live state") { retained_payloads(client, "placeos/#{org}/#").has_key?(live) }
        retained = retained_payloads(client, "placeos/#{org}/#")
        retained.keys.should eq [live]
        JSON.parse(retained[live])["value"].should eq true

        metadata = retained_payloads(client, "placeos/#{Mappings.scope}/metadata/#")
        metadata.has_key?(stale_metadata).should be_false
        metadata.has_key?("placeos/#{Mappings.scope}/metadata/#{zone.id}").should be_true
      ensure
        manager.try &.status_events.stop
      end
    ensure
      client.try &.disconnect
      store.try &.clear
      zone.try &.destroy
      mod.try &.destroy
    end
  end

  describe "clearing retained state" do
    it "publishes an event that arrives during the clear once it is done" do
      org = "org-#{UUID.random}"
      module_id = "mod-#{UUID.random}"
      mappings = Mappings.new(mock_state(module_id: module_id, org_id: org))

      # registered, so a sweep running meanwhile keeps them: only the clear
      # removes them
      topics = Array.new(40) do |i|
        event = mappings.status_events?(module_id, "status_#{i}").not_nil!.first
        mappings.published.add(event)
        MqttPublisher.generate_key(event).not_nil!
      end
      live_event = mappings.status_events?(module_id, "power").not_nil!.first
      live = MqttPublisher.generate_key(live_event).not_nil!

      client = subscriber
      topics.each { |topic| client.publish(topic, %({"value":true}), retain: true) }

      publisher = ControlledPublisher.new(isolated_broker)
      started = Channel(Nil).new(1)
      signalled = false
      publisher.on_delete = ->(topic : String) {
        if !signalled && topic.includes?(org)
          signalled = true
          started.send(nil)
        end
        nil
      }
      publisher.start

      events = StatusEvents.new(mappings, [manager_for(publisher)] of PublisherManager)
      spawn { events.start }
      wait_for("the initial sync") { events.initial_sync_complete? }

      done = Channel(Int64).new(1)
      # rounds of 10, so the clear is still going when the event arrives
      spawn { done.send events.clear_retained(batch: 10) }

      select
      when started.receive
      when timeout(30.seconds)
        raise "the clear never started removing topics"
      end

      Redis.open(url: REDIS_URL) do |redis|
        redis.publish("status/#{module_id}/power", "true")
      end

      select
      when cleared = done.receive
        cleared.should be >= 40
      when timeout(60.seconds)
        raise "the clear never finished"
      end

      wait_for("the event to be published") { !mappings.published.for_module(module_id).empty? }
      mappings.published.for_module(module_id).should eq Set{live_event}
      wait_for("the event to be retained") { retained_payloads(client, "placeos/#{org}/#").has_key?(live) }
      retained_payloads(client, "placeos/#{org}/#").keys.should eq [live]
    ensure
      events.try &.stop
      publisher.try &.stop rescue nil
      client.try { |c| c.publish(live.not_nil!, "", retain: true) rescue nil; c.disconnect }
    end

    it "gives up on topics whose removal never reaches the broker" do
      org = "org-#{UUID.random}"
      topics = Array.new(3) { |i| "placeos/#{org}/state/b/l/a/cs-1/driver-1/Display/#{i}/power" }
      client = subscriber
      topics.each { |topic| client.publish(topic, %({"value":true}), retain: true) }

      publisher = ControlledPublisher.new(isolated_broker)
      publisher.drop_deletes = true
      publisher.start
      events = StatusEvents.new(Mappings.new, [manager_for(publisher)] of PublisherManager)

      done = Channel(Int64).new(1)
      spawn { done.send events.clear_retained }

      select
      when cleared = done.receive
        # nothing reached the broker, so nothing was removed
        cleared.should eq 0
      when timeout(60.seconds)
        raise "the clear never finished"
      end

      retained_payloads(client, "placeos/#{org}/#").keys.sort.should eq topics.sort
    ensure
      publisher.try &.stop rescue nil
      if client
        topics.try &.each { |topic| client.publish(topic, "", retain: true) }
        client.disconnect
      end
    end
  end

  describe Api::Root do
    it "starts a resync, refuses a second, and reports where it got to" do
      previous = Manager.instance
      # never started, so it waits on the initial sync and stays running
      Manager.instance = Manager.new([] of PublisherManager)
      client = ActionController::SpecHelper.client

      response = client.post("/api/source/v1/resync?clear=true")
      response.status_code.should eq 202
      status = Manager::ResyncStatus.from_json(response.body)
      status.state.clearing?.should be_true
      status.clear?.should be_true

      response = client.post("/api/source/v1/resync")
      response.status_code.should eq 409
      Manager::ResyncStatus.from_json(response.body).state.clearing?.should be_true

      response = client.get("/api/source/v1/resync")
      response.status_code.should eq 200
      status = Manager::ResyncStatus.from_json(response.body)
      status.state.clearing?.should be_true
      status.started_at.should_not be_nil
    ensure
      Manager.instance = previous if previous
    end
  end
end
