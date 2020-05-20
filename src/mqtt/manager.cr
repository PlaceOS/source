require "./publisher_manager"
require "./router"

module PlaceOS::MQTT
  class Manager
    getter router : Router
    getter publisher_manager : PublisherManager

    getter? started = false

    @@instance : Manager?

    def self.instance : Manager
      (@@instance ||= Manager.new).as(Manager)
    end

    def initialize(
      @router : Router = Router.new,
      @publisher_manager : PublisherManager = PublisherManager.new
    )
    end

    def start
      return if started?
      @started = true

      Log.info { "registering Brokers" }
      publisher_manager.start

      Log.info { "routing table events" }
      router.start
    end

    def stop
      return unless started?

      @started = false
      publisher_manager.stop
      router.stop
    end
  end
end
