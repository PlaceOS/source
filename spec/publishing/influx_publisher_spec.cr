require "../spec_helper"
require "time"

module PlaceOS::Source
  describe InfluxPublisher do
    describe "#transform" do
      it "ignores PlaceOS Metadata events" do
        message = Publisher::Message.new(
          data: Mappings::Metadata.new("some-model-id"),
          payload: nil,
        )
        point = InfluxPublisher.transform(message)
        point.should be_nil
      end

      it "transforms a PlaceOS Status event to an InfluxDB point" do
        state = mock_state(
          module_id: "mod-1234",
          index: 1,
          module_name: "M'Odule",
          driver_id: "12345",
          control_system_id: "cs-9445",
          area_id: "2042",
          level_id: "nek",
          building_id: "cards",
          org_id: "org-donor",
        )

        status_event = Mappings.new(state).status_events?("mod-1234", "power").not_nil!.first

        message = Publisher::Message.new(status_event, "false")

        point = InfluxPublisher.transform(message)
        point.should_not be_nil
        point = point.not_nil!

        point.measurement.should eq "M'Odule"

        point.timestamp.should eq Time::UNIX_EPOCH

        point.tags.should eq({
          :org      => "org-donor",
          :building => "cards",
        })

        point.fields.should eq({
          :level  => "nek",
          :area   => "2042",
          :system => "cs-9445",
          :driver => "12345",
          :index  => 1,
          :state  => "power",
          :value  => false,
        })
      end
    end
  end
end
