require "../spec_helper"

module PlaceOS::MQTT
  describe Publisher do
    describe "events" do
      it "metadata" do
        payload = %({"hello": "world"})
        id = "model-12345"
        scope = "zone-big1"
        message = Publisher.metadata(scope, id, payload)
        message.key.should eq File.join(MQTT_NAMESPACE, scope, "metadata", id)
        message.payload.should eq payload
      end

      it "empty payload metadata" do
        id = "model-12345"
        scope = "zone-big1"
        nil_message = Publisher.metadata(scope, id, nil)
        nil_message.key.should eq File.join(MQTT_NAMESPACE, scope, "metadata", id)
        nil_message.payload.should be_nil
      end

      it "state" do
        payload = %({"hello": "world"})
        key = "key"
        message = Publisher.state(key, payload)
        message.key.should eq key
        message.payload.should eq payload
      end
    end
  end
end
