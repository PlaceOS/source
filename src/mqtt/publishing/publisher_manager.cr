require "./publisher"

module PlaceOS::Ingest
  module PublisherManager
    abstract def broadcast(message : Publisher::Message)
    abstract def start
    abstract def stop
  end
end
