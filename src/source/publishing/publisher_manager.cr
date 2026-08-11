require "./publisher"

module PlaceOS::Source
  module PublisherManager
    abstract def broadcast(message : Publisher::Message)

    # Queues removal of whatever is retained for the message's key
    abstract def broadcast_delete(message : Publisher::Message)

    # Whether any publisher still has deletions to deal with
    abstract def deletes_pending? : Bool

    abstract def start
    abstract def stop

    abstract def stats : Hash(String, UInt64)
  end
end
