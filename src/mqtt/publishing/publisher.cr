require "../constants"

module PlaceOS::Ingest
  abstract class Publisher
    Log = ::Log.for(self)

    record Message,
      data : Mappings::Data,
      payload : String?

    getter message_queue : Channel(Message) = Channel(Message).new

    abstract def publish(message : Message)

    def start
      consume_messages
    end

    def stop
      message_queue.close
    end

    def self.timestamp
      Time.utc
    end

    private def consume_messages
      spawn do
        while message = message_queue.receive?
          publish(message)
        end
      end
    end
  end
end
