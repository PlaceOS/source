require "../spec_helper"

module PlaceOS::MQTT
  describe Router::Module do
    describe "system_modules" do
      pending "updates on changes to Module name" do
      end

      pending "removes reference on Module destroy" do
      end
    end

    describe "drivers" do
      it "keeps a reference from module_id to driver_id" do
        driver = Model::Generator.driver(module_name: "mock")
        driver.id = "driver-sns"
        mod = Model::Generator.module(driver)
        mod.id = "mod-1234"

        mappings = Mappings.new

        router = Router::Module.new(mappings)

        router.handle_create(mod)

        mappings.@state.drivers["mod-1234"].should eq "driver-sns"
      end

      it "removes module_id reference on destroy" do
        driver = Model::Generator.driver(module_name: "mock")
        driver.id = "driver-sns"
        mod = Model::Generator.module(driver)
        mod.id = "mod-1234"

        state = Mappings::State.new
        state.drivers["mod-1234"] = "driver-sns"
        mappings = Mappings.new(state)

        router = Router::Module.new(mappings)

        router.handle_delete(mod)

        state.drivers["mod-1234"]?.should be_nil
      end
    end
  end
end
