require "../constants"

module PlaceOS::Source
  abstract class Publisher
    Log = ::Log.for(self)

    record(
      Message,
      data : Mappings::Data,
      payload : String?,
      timestamp : Time
    )

    getter message_queue : Channel(Message) = Channel(Message).new(StatusEvents::BATCH_SIZE)
    getter processed : UInt64 = 0_u64

    abstract def publish(message : Message)

    def start
      spawn { consume_messages }
    end

    def stop
      message_queue.close
    end

    private def consume_messages
      while message = message_queue.receive?
        begin
          publish(message)
          @processed += 1_u64
        rescue error
          Log.warn(exception: error) { "publishing message: #{message}" }
        end
      end
    end
  end
end
