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
        points = InfluxPublisher.transform(message)
        points.empty?.should be_true
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

        point = InfluxPublisher.transform(message)[0]
        point.should_not be_nil
        point = point.not_nil!

        point.measurement.should eq "M'Odule"

        point.timestamp.should eq Time::UNIX_EPOCH

        point.tags.should eq({
          "pos_org"      => "org-donor",
          "pos_building" => "cards",
          "pos_level"    => "nek",
          "pos_area"     => "2042",
          "pos_system"   => "cs-9445",
          "pos_module"   => "M'Odule",
          "pos_index"    => "1",
        })

        point.fields.should eq({
          "pos_driver" => "12345",
          "power"      => false,
          "pos_key"    => "power",
        })
      end

      it "transforms a hash status event to an InfluxDB point" do
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

        status_event = Mappings.new(state).status_events?("mod-1234", "state").not_nil!.first

        message = Publisher::Message.new(status_event, {
          hello: "world",
          temp:  30.5,
          id:    nil,
          other: false,
        }.to_json)

        point = InfluxPublisher.transform(message)[0]
        point.should_not be_nil
        point = point.not_nil!

        point.measurement.should eq "M'Odule"

        point.timestamp.should eq Time::UNIX_EPOCH

        point.tags.should eq({
          "pos_org"      => "org-donor",
          "pos_building" => "cards",
          "pos_level"    => "nek",
          "pos_area"     => "2042",
          "pos_system"   => "cs-9445",
          "pos_module"   => "M'Odule",
          "pos_index"    => "1",
        })

        point.fields.should eq({
          "pos_driver" => "12345",
          "pos_key"    => "state",
          "hello"      => "world",
          "temp"       => 30.5,
          "other"      => false,
        })
      end

      it "transforms a complex status event to an InfluxDB point" do
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

        status_event = Mappings.new(state).status_events?("mod-1234", "state").not_nil!.first

        message = Publisher::Message.new(status_event, {
          value: [{
            "location"          => "wireless",
            "coordinates_from"  => "bottom-left",
            "x"                 => 27.113065326953013,
            "y"                 => 36.85052447328469,
            "lon"               => 55.27498749637098,
            "lat"               => 25.20090608906493,
            "s2_cell_id"        => "12345",
            "mac"               => "66e0fd1279ce",
            "variance"          => 4.5194575835650745,
            "last_seen"         => 1601555879,
            "building"          => "zone-EmWLJNm0i~6",
            "level"             => "zone-Epaq-dE1DaH",
            "map_width"         => 1234.2,
            "map_height"        => 123.8,
            "meraki_floor_id"   => "g_727894289736675",
            "meraki_floor_name" => "BUILDING Name - L2",
          }, {
            "location"    => "desk",
            "at_location" => false,
            "map_id"      => "desk-4-1006",
            "mac"         => "66e0fd1279ce",
            "level"       => "zone_1234",
            "building"    => "zone_1234",
          }],
          ts_hint: "complex",
          ts_map:  {
            x: "xloc",
            y: "yloc",
          },
          ts_tag_keys: {"s2_cell_id"},
          ts_fields:   {
            pos_level: "not-nek",
          },
          ts_tags: {
            pos_building: "pack",
          },
        }.to_json)

        points = InfluxPublisher.transform(message)
        point = points[0]
        point.should_not be_nil
        point = point.not_nil!

        point.measurement.should eq "M'Odule"

        point.timestamp.should eq Time::UNIX_EPOCH

        point.tags.should eq({
          "pos_org"      => "org-donor",
          "pos_building" => "pack",
          "pos_level"    => "nek",
          "pos_area"     => "2042",
          "pos_system"   => "cs-9445",
          "pos_module"   => "M'Odule",
          "pos_index"    => "1",
          "pos_uniq"     => "0",
          "s2_cell_id"   => "12345",
        })

        point.fields.should eq({
          "pos_level"         => "not-nek",
          "pos_driver"        => "12345",
          "pos_key"           => "state",
          "location"          => "wireless",
          "coordinates_from"  => "bottom-left",
          "xloc"              => 27.113065326953013,
          "yloc"              => 36.85052447328469,
          "lon"               => 55.27498749637098,
          "lat"               => 25.20090608906493,
          "mac"               => "66e0fd1279ce",
          "variance"          => 4.5194575835650745,
          "last_seen"         => 1601555879,
          "building"          => "zone-EmWLJNm0i~6",
          "level"             => "zone-Epaq-dE1DaH",
          "map_width"         => 1234.2,
          "map_height"        => 123.8,
          "meraki_floor_id"   => "g_727894289736675",
          "meraki_floor_name" => "BUILDING Name - L2",
        })

        point = points[1]
        point.should_not be_nil
        point = point.not_nil!

        point.measurement.should eq "M'Odule"

        point.timestamp.should eq Time::UNIX_EPOCH

        point.tags.should eq({
          "pos_org"      => "org-donor",
          "pos_building" => "pack",
          "pos_level"    => "nek",
          "pos_area"     => "2042",
          "pos_system"   => "cs-9445",
          "pos_module"   => "M'Odule",
          "pos_index"    => "1",
          "pos_uniq"     => "1",
        })

        point.fields.should eq({
          "pos_level"   => "not-nek",
          "pos_driver"  => "12345",
          "pos_key"     => "state",
          "location"    => "desk",
          "at_location" => false,
          "map_id"      => "desk-4-1006",
          "mac"         => "66e0fd1279ce",
          "level"       => "zone_1234",
          "building"    => "zone_1234",
        })
      end

      it "transforms an array of hashes" do
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

        status_event = Mappings.new(state).status_events?("mod-1234", "state").not_nil!.first

        message = Publisher::Message.new(status_event, [{
          "measurement"       => "custom_measurement",
          "location"          => "wireless",
          "coordinates_from"  => "bottom-left",
          "x"                 => 27.113065326953013,
          "y"                 => 36.85052447328469,
          "lon"               => 55.27498749637098,
          "lat"               => 25.20090608906493,
          "s2_cell_id"        => "12345",
          "mac"               => "66e0fd1279ce",
          "variance"          => 4.5194575835650745,
          "last_seen"         => 1601555879,
          "building"          => "zone-EmWLJNm0i~6",
          "level"             => "zone-Epaq-dE1DaH",
          "map_width"         => 1234.2,
          "map_height"        => 123.8,
          "meraki_floor_id"   => "g_727894289736675",
          "meraki_floor_name" => "BUILDING Name - L2",
        }, {
          "location"    => "desk",
          "at_location" => false,
          "map_id"      => "desk-4-1006",
          "mac"         => "66e0fd1279ce",
          "level"       => "zone_1234",
          "building"    => "zone_1234",
        }].to_json)

        points = InfluxPublisher.transform(message)
        point = points[0]
        point.should_not be_nil
        point = point.not_nil!

        point.measurement.should eq "custom_measurement"

        point.timestamp.should eq Time::UNIX_EPOCH

        point.tags.should eq({
          "pos_org"      => "org-donor",
          "pos_building" => "cards",
          "pos_level"    => "nek",
          "pos_area"     => "2042",
          "pos_system"   => "cs-9445",
          "pos_module"   => "M'Odule",
          "pos_index"    => "1",
          "pos_uniq"     => "0",
        })

        point.fields.should eq({
          "pos_driver"        => "12345",
          "pos_key"           => "state",
          "location"          => "wireless",
          "coordinates_from"  => "bottom-left",
          "x"                 => 27.113065326953013,
          "y"                 => 36.85052447328469,
          "lon"               => 55.27498749637098,
          "lat"               => 25.20090608906493,
          "s2_cell_id"        => "12345",
          "mac"               => "66e0fd1279ce",
          "variance"          => 4.5194575835650745,
          "last_seen"         => 1601555879,
          "building"          => "zone-EmWLJNm0i~6",
          "level"             => "zone-Epaq-dE1DaH",
          "map_width"         => 1234.2,
          "map_height"        => 123.8,
          "meraki_floor_id"   => "g_727894289736675",
          "meraki_floor_name" => "BUILDING Name - L2",
        })

        point = points[1]
        point.should_not be_nil
        point = point.not_nil!

        point.measurement.should eq "M'Odule"

        point.timestamp.should eq Time::UNIX_EPOCH

        point.tags.should eq({
          "pos_org"      => "org-donor",
          "pos_building" => "cards",
          "pos_level"    => "nek",
          "pos_area"     => "2042",
          "pos_system"   => "cs-9445",
          "pos_module"   => "M'Odule",
          "pos_index"    => "1",
          "pos_uniq"     => "1",
        })

        point.fields.should eq({
          "pos_driver"  => "12345",
          "pos_key"     => "state",
          "location"    => "desk",
          "at_location" => false,
          "map_id"      => "desk-4-1006",
          "mac"         => "66e0fd1279ce",
          "level"       => "zone_1234",
          "building"    => "zone_1234",
        })
      end
    end
  end
end
