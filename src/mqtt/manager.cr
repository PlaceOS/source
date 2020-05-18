require "./broker_listener"
require "./router"

module PlaceOS::MQTT
  class Manager
    getter router : Router
    getter broker_listener : BrokerListener

    getter? started = false

    @@instance : Manager?

    def self.instance : Manager
      (@@instance ||= Manager.new).as(Manager)
    end

    def initialize(
      @router : Router = Router.new,
      @broker_listener : BrokerListener = BrokerListener.new,
    )
    end

    def start
      return if started?
      @started = true

      Log.info { "registering Brokers" }
      broker_listener.start

      Log.info { "routing table events" }
      router.start
    end

    def stop
      return unless started?

      @started = false
      broker_listener.stop
      router.stop
    end
  end
end
