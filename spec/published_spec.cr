require "./spec_helper"

module PlaceOS::Source
  def self.published_status(module_id : String, control_system_id : String, status : String) : Mappings::Status
    Mappings::Status.new(
      status: status,
      index: 1,
      module_name: "Display",
      module_id: module_id,
      driver_id: "driver-1",
      control_system_id: control_system_id,
      zone_mapping: {"org" => "org-1"},
    )
  end

  describe Published do
    it "finds what is published by system" do
      published = Published.new
      a_power = published_status("mod-a", "cs-1", "power")
      a_input = published_status("mod-a", "cs-1", "input")
      a_other = published_status("mod-a", "cs-2", "power")
      b_power = published_status("mod-b", "cs-2", "power")
      [a_power, a_input, a_other, b_power].each { |event| published.add(event) }
      # adding twice is not counted twice
      published.add(a_power)

      published.module_ids_in({"cs-1"}).should eq Set{"mod-a"}
      published.module_ids_in({"cs-2"}).should eq Set{"mod-a", "mod-b"}
      published.for_system("cs-1").to_set.should eq Set{a_power, a_input}

      published.remove(a_power)
      published.module_ids_in({"cs-1"}).should eq Set{"mod-a"}
      published.remove(a_input)
      published.module_ids_in({"cs-1"}).should be_empty
      published.for_system("cs-1").should be_empty
      # removing what is not there changes nothing
      published.remove(a_input)
      published.module_ids_in({"cs-2"}).should eq Set{"mod-a", "mod-b"}
      published.for_module("mod-a").should eq Set{a_other}
    end
  end
end
