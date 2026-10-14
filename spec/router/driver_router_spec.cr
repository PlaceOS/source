require "../spec_helper"

module PlaceOS::Source
  describe Router::Driver do
    # driver_id is a topic segment, so a destroyed Driver leaves every module
    # that referenced it without a mapping
    it "removes references to Driver on destroy" do
      state = Mappings::State.new
      state.drivers["mod-keep"] = "driver-other"
      state.drivers["mod-drop-1"] = "driver-gone"
      state.drivers["mod-drop-2"] = "driver-gone"
      mappings = Mappings.new(state)

      driver = Model::Generator.driver(module_name: "mock")
      driver.id = "driver-gone"
      driver.destroy

      router = Router::Driver.new(mappings, [] of PublisherManager)
      router.process_resource(:deleted, driver).should eq Resource::Result::Success

      drivers = mappings.read(&.drivers)
      drivers.should eq({"mod-keep" => "driver-other"})
    end

    # while loading, scope is read from the mappings, not the database
    it "publishes a loaded Driver's metadata once, if it has a Module in scope" do
      state = Mappings::State.new
      state.drivers["mod-a"] = "driver-scoped"
      state.drivers["mod-b"] = "driver-scoped"
      state.drivers["mod-c"] = "driver-unscoped"
      state.map_module("mod-a", {name: "Display", control_system_id: "cs-1", index: 1})
      state.map_module("mod-b", {name: "Display", control_system_id: "cs-2", index: 1})
      state.map_module("mod-c", {name: "Display", control_system_id: "cs-3", index: 1})
      state.system_zones["cs-1"] = {Mappings.scope => "org-1", "building" => "b"}
      state.system_zones["cs-2"] = {Mappings.scope => "org-2"}
      state.system_zones["cs-3"] = {"building" => "b"}
      manager = MockManager.new
      router = Router::Driver.new(Mappings.new(state), [manager] of PublisherManager)

      scoped = Model::Generator.driver(module_name: "mock")
      scoped.id = "driver-scoped"
      unscoped = Model::Generator.driver(module_name: "mock")
      unscoped.id = "driver-unscoped"

      router.process_resource(:created, scoped).should eq Resource::Result::Success
      router.process_resource(:created, unscoped).should eq Resource::Result::Skipped

      manager.messages.map(&.data).should eq [Mappings::Metadata.new("driver-scoped")]
    end
  end
end
