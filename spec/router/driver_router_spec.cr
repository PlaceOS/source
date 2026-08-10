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
  end
end
