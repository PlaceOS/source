require "./publisher_manager"

module PlaceOS::Ingest
  class InfluxManager
    include PublisherManager
    # set up the publisher,
    # pass the message to the publisher in the broadcast
  end
end
