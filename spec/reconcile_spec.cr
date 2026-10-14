require "./spec_helper"
require "placeos-driver/storage"

module PlaceOS::Source
  # A system `cs-1` in a resolvable hierarchy, with the given Modules in order.
  # Modules of the same name are numbered by position, as source does it
  def self.reconcile_mappings(org : String, modules : Array({String, String})) : Mappings
    state = Mappings::State.new
    state.system_zones["cs-1"] = {"org" => org, "building" => "b", "level" => "l", "area" => "a"}
    mappings = Mappings.new(state)
    place(mappings, modules)
    modules.each { |(module_id, _)| state.drivers[module_id] = "driver-1" }
    mappings
  end

  def self.place(mappings : Mappings, modules : Array({String, String})) : Nil
    counts = Hash(String, Int32).new(0)
    mapping = modules.each_with_object({} of String => Mappings::SystemModule) do |(module_id, name), hash|
      hash[module_id] = {name: name, control_system_id: "cs-1", index: counts[name] += 1}
    end
    mappings.set_system_modules("cs-1", mapping)
  end

  # what each queued message would publish to, and its payload
  def self.keyed(messages : Array(Publisher::Message)) : Hash(String, String?)
    messages.to_h { |m| {MqttPublisher.generate_key(m.data).not_nil!.split('/')[-3..].join('/'), m.payload} }
  end

  def self.stored(module_id : String, values : Hash(String, String)) : PlaceOS::Driver::RedisStorage
    store = PlaceOS::Driver::RedisStorage.new(module_id)
    store.clear
    values.each { |key, value| store[key] = value }
    store
  end

  describe "reconciling retained state" do
    it "publishes the current state of a Module it has not published" do
      a = "mod-#{UUID.random}"
      store = stored(a, {"connected" => "true", "power" => "false"})
      mappings = reconcile_mappings("org-#{UUID.random}", [{a, "Display"}])
      manager = MockManager.new
      events = StatusEvents.new(mappings, [manager] of PublisherManager)

      events.reconcile_now(Set{a})

      keyed(manager.messages).should eq({"Display/1/connected" => "true", "Display/1/power" => "false"})
      manager.deletions.should be_empty
      mappings.published.for_module(a).size.should eq 2
    ensure
      store.try &.clear
    end

    it "moves each Module's state to its new index when a system is reordered" do
      a, b = "mod-#{UUID.random}", "mod-#{UUID.random}"
      store_a = stored(a, {"which" => %("a")})
      store_b = stored(b, {"which" => %("b")})
      mappings = reconcile_mappings("org-#{UUID.random}", [{a, "Display"}, {b, "Display"}])
      manager = MockManager.new
      events = StatusEvents.new(mappings, [manager] of PublisherManager)
      events.reconcile_now(Set{a, b})
      manager.messages.clear

      place(mappings, [{b, "Display"}, {a, "Display"}])
      events.reconcile_now(mappings.take_reconcile | Set{a, b})

      keyed(manager.messages).should eq({"Display/1/which" => %("b"), "Display/2/which" => %("a")})
      # both old topics are taken over by the other Module, so neither is removed
      manager.deletions.should be_empty
    ensure
      store_a.try &.clear
      store_b.try &.clear
    end

    it "removes the topics of a Module taken out of a system" do
      a, b = "mod-#{UUID.random}", "mod-#{UUID.random}"
      store_a = stored(a, {"connected" => "false"})
      store_b = stored(b, {"connected" => "true"})
      mappings = reconcile_mappings("org-#{UUID.random}", [{a, "Display"}, {b, "Display"}])
      manager = MockManager.new
      events = StatusEvents.new(mappings, [manager] of PublisherManager)
      events.reconcile_now(Set{a, b})
      manager.messages.clear

      # b moves up to Display_1, which a held; Display_2 is left with nothing
      place(mappings, [{b, "Display"}])
      events.reconcile_now(Set{a, b})

      keyed(manager.messages).should eq({"Display/1/connected" => "true"})
      keyed(manager.deletions).keys.should eq ["Display/2/connected"]
      mappings.published.for_module(a).should be_empty
    ensure
      store_a.try &.clear
      store_b.try &.clear
    end

    it "removes a deleted Module's topics even once its storage is gone" do
      a = "mod-#{UUID.random}"
      store = stored(a, {"connected" => "false", "power" => "true"})
      mappings = reconcile_mappings("org-#{UUID.random}", [{a, "Display"}])
      manager = MockManager.new
      events = StatusEvents.new(mappings, [manager] of PublisherManager)
      events.reconcile_now(Set{a})

      # core clears the storage, and the system drops the Module, before the
      # Module's own delete event is seen
      store.clear
      place(mappings, [] of {String, String})
      events.reconcile_now(Set{a})

      keyed(manager.deletions).keys.sort.should eq ["Display/1/connected", "Display/1/power"]
      mappings.published.for_module(a).should be_empty
    ensure
      store.try &.clear
    end

    it "removes the topics of a system that is gone" do
      a = "mod-#{UUID.random}"
      store = stored(a, {"connected" => "true"})
      mappings = reconcile_mappings("org-#{UUID.random}", [{a, "Display"}])
      manager = MockManager.new
      events = StatusEvents.new(mappings, [manager] of PublisherManager)
      events.reconcile_now(Set{a})

      mappings.remove_system_modules("cs-1")
      mappings.reconcile_systems({"cs-1"})
      events.reconcile_now(mappings.take_reconcile)

      keyed(manager.deletions).keys.should eq ["Display/1/connected"]
    ensure
      store.try &.clear
    end

    it "sweeps retained topics that nothing maps to" do
      a = "mod-#{UUID.random}"
      org = "org-#{UUID.random}"
      store = stored(a, {"connected" => "true"})
      mappings = reconcile_mappings(org, [{a, "Display"}])
      events = StatusEvents.new(mappings, [MockManager.new] of PublisherManager)
      events.reconcile_now(Set{a})

      live = MqttPublisher.generate_key(mappings.published.for_module(a).first).not_nil!
      stale = live.sub("/Display/1/", "/Display/9/")
      publisher = SweepRecorder.new
      events.sweep_now(publisher, Set{live, stale})

      publisher.topics.should eq [stale]
    ensure
      store.try &.clear
    end
  end

  private class SweepRecorder < Publisher
    getter topics = [] of String

    def publish(message : Publisher::Message)
    end

    def queue_delete_topic(topic : String) : Nil
      topics << topic
    end
  end
end
