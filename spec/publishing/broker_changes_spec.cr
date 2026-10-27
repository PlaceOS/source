require "../spec_helper"

module PlaceOS::Source
  # Brokers are added, edited and removed in the database while source runs.
  # These go through the changefeed, as they do in production
  describe MqttBrokerManager, tags: "broker-changes" do
    managers = [] of MqttBrokerManager
    brokers = [] of Model::Broker
    relays = [] of BrokerRelay

    # Every example has a Broker of its own, so the client ids never collide
    new_broker = ->(port : Int32) {
      shared = test_broker
      broker = Model::Broker.new(
        name: "changes-#{UUID.random}",
        host: port == shared.port ? shared.host : "127.0.0.1",
        port: port,
        auth_type: :user_password,
        username: "source",
        password: "first",
      ).save!
      brokers << broker
      broker
    }

    start_manager = -> {
      manager = MqttBrokerManager.new
      managers << manager
      manager.start
      manager
    }

    publisher_for = ->(manager : MqttBrokerManager, broker : Model::Broker) {
      manager.@publishers[broker.id.as(String)]?
    }

    # A port nothing is listening on, yet
    free_port = -> {
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      server.close
      port
    }

    after_each do
      managers.each do |manager|
        manager.stop
        manager.publishers.each(&.stop)
      end
      managers.clear
      brokers.each { |broker| broker.destroy rescue nil }
      brokers.clear
      relays.each(&.cut)
      relays.clear
    end

    it "connects to a broker added to the database" do
      manager = start_manager.call
      broker = new_broker.call(test_broker.port)

      eventually { publisher_for.call(manager, broker).try { |pub| !pub.client.closed? } }
    end

    it "reconnects with the new password when it changes" do
      manager = start_manager.call
      broker = new_broker.call(test_broker.port)
      eventually { publisher_for.call(manager, broker) }
      original = publisher_for.call(manager, broker).not_nil!

      broker.password = "second"
      broker.save!

      eventually { publisher_for.call(manager, broker).try &.broker.password.== "second" }
      replacement = publisher_for.call(manager, broker).not_nil!
      replacement.should_not be original
      eventually { !replacement.client.closed? }
      original.client.closed?.should be_true
    end

    it "keeps the connection when only the name changes" do
      manager = start_manager.call
      broker = new_broker.call(test_broker.port)
      eventually { publisher_for.call(manager, broker) }
      original = publisher_for.call(manager, broker).not_nil!

      broker.name = "renamed-#{UUID.random}"
      broker.save!

      eventually { publisher_for.call(manager, broker).try &.broker.name.== broker.name }
      publisher_for.call(manager, broker).should be original
      original.client.closed?.should be_false
    end

    it "moves to a new address once it is reachable" do
      manager = start_manager.call
      broker = new_broker.call(test_broker.port)
      eventually { publisher_for.call(manager, broker) }

      port = free_port.call
      broker.host = "127.0.0.1"
      broker.port = port
      broker.save!

      # the new address is not up yet
      sleep 2.seconds
      relays << BrokerRelay.new(test_broker.host, test_broker.port, port)

      eventually(40.seconds) { publisher_for.call(manager, broker).try { |pub| pub.broker.port == port && !pub.client.closed? } }
    end

    it "republishes state to the broker at a new address" do
      manager = start_manager.call
      ready = [] of String
      manager.on_broker_ready = ->(id : String) { ready << id; nil }
      broker = new_broker.call(test_broker.port)
      eventually { publisher_for.call(manager, broker) }
      ready.clear

      relay = BrokerRelay.new(test_broker.host, test_broker.port)
      relays << relay
      broker.host = "127.0.0.1"
      broker.port = relay.port
      broker.save!

      eventually { publisher_for.call(manager, broker).try &.broker.port.== relay.port }
      eventually { ready.includes?(broker.id) }
    end

    it "ends up with the last of several quick changes" do
      manager = start_manager.call
      broker = new_broker.call(test_broker.port)
      eventually { publisher_for.call(manager, broker) }

      %w[a b c d e].each do |password|
        broker.password = password
        broker.save!
      end

      sleep 3.seconds
      publisher = publisher_for.call(manager, broker).not_nil!
      publisher.broker.password.should eq "e"
      publisher.client.closed?.should be_false
      manager.publishers.count(&.broker.id.== broker.id).should eq 1
    end

    it "disconnects from a broker removed from the database" do
      manager = start_manager.call
      broker = new_broker.call(test_broker.port)
      eventually { publisher_for.call(manager, broker) }
      publisher = publisher_for.call(manager, broker).not_nil!

      broker.destroy

      eventually { publisher_for.call(manager, broker).nil? }
      eventually { publisher.client.closed? }
    end
  end
end

def eventually(timeout : Time::Span = 15.seconds, &)
  deadline = Time.instant + timeout
  until yield
    raise "timed out after #{timeout}" if Time.instant > deadline
    sleep 100.milliseconds
  end
end
