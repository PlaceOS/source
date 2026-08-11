require "../spec_helper"

module PlaceOS::Source
  describe Router::Module do
    describe "system_modules" do
      # the module name is a topic segment, so a rename moves the topic
      it "updates on changes to Module name" do
        state = Mappings::State.new
        state.system_modules["mod-renamed"] = [
          {name: "Old Name", control_system_id: "cs-1", index: 1},
        ]
        mappings = Mappings.new(state)

        mappings.set_system_modules("cs-1", {
          "mod-renamed" => {name: "New Name", control_system_id: "cs-1", index: 1},
        })

        entries = mappings.read { |current| current.system_modules["mod-renamed"] }
        entries.size.should eq 1
        # replaced rather than accumulated, or the module would publish to both
        entries.first[:name].should eq "New Name"
      end

      it "updates on changes to Module index" do
        state = Mappings::State.new
        state.system_modules["mod-reindexed"] = [
          {name: "M'Odule", control_system_id: "cs-1", index: 1},
        ]
        mappings = Mappings.new(state)

        mappings.set_system_modules("cs-1", {
          "mod-reindexed" => {name: "M'Odule", control_system_id: "cs-1", index: 2},
        })

        entries = mappings.read { |current| current.system_modules["mod-reindexed"] }
        entries.size.should eq 1
        entries.first[:index].should eq 2
      end

      it "removes reference on Module destroy" do
        state = Mappings::State.new
        state.drivers["mod-gone"] = "driver-sns"
        state.drivers["mod-stays"] = "driver-sns"
        state.system_modules["mod-gone"] = [
          {name: "M'Odule", control_system_id: "cs-1", index: 1},
        ]
        mappings = Mappings.new(state)

        driver = Model::Generator.driver(module_name: "mock")
        driver.id = "driver-sns"
        mod = Model::Generator.module(driver)
        mod.id = "mod-gone"

        Router::Module.new(mappings).handle_delete(mod)

        mappings.read(&.drivers).should eq({"mod-stays" => "driver-sns"})
        mappings.read(&.system_modules.has_key?("mod-gone")).should be_false
      end
    end

    describe "drivers" do
      before_each { Model::Driver.clear }
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
