require "./spec_helper"

module PlaceOS::Source
  describe "clearing retained state" do
    # several rounds, as a broker that drops part of a large subscription needs
    it "removes every state and metadata topic, in rounds, and nothing else" do
      with_publisher do |publisher|
        publisher.start
        manager = MqttBrokerManager.new
        manager.@publishers[publisher.broker.id.as(String)] = publisher
        mappings = Mappings.new
        event, _ = unique_status_event
        mappings.published.add(event)
        events = StatusEvents.new(mappings, [manager] of PublisherManager)

        org = "org-#{UUID.random}"
        state = Array.new(45) { |i| "placeos/#{org}/state/b/l/a/cs-1/driver-1/Display/#{i}/power" }
        metadata = Array.new(5) { |i| "placeos/#{org}/metadata/sys-#{i}" }
        other = "elsewhere/#{org}/keep"
        client = subscriber
        (state + metadata + [other]).each { |topic| client.publish(topic, %({"value":true}), retain: true) }

        mine = ->(topic : String) { topic.includes?(org) }
        publisher.retained_topics("placeos/#{org}/#", &mine).size.should eq 50

        events.clear_retained(batch: 20).should be >= 50

        publisher.retained_topics("placeos/#{org}/#", &mine).should be_empty
        publisher.retained_topics("elsewhere/#{org}/#", &mine).should eq Set{other}
        mappings.published.for_module(event.module_id).should be_empty

        client.publish(other, "", retain: true)
        client.disconnect
      end
    end
  end
end
