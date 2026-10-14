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

    # A retained value to remove: either the key a message would publish to, or
    # a topic by name, for one that nothing maps to any more
    record(
      Deletion,
      message : Message? = nil,
      topic : String? = nil
    )

    # Publications and deletions, in the order they were made.
    #
    # NOTE:: ONE queue, so a deletion can never overtake a publication made
    # before it, or be overtaken by one made after. Deletions used to have a
    # queue of their own that was drained first, which let a removal jump ahead
    # of a stale value still waiting to be published — the value then came
    # back. Ordering is enough now because a deletion is only ever queued for a
    # topic that nothing maps to (`Reconciler`), so a later publication to the
    # same topic is, by construction, a value that belongs there
    getter message_queue : Channel(Message | Deletion) = Channel(Message | Deletion).new(StatusEvents::BATCH_SIZE)

    getter processed : UInt64 = 0_u64
    getter deleted : UInt64 = 0_u64

    # NOTE:: counted rather than asking the channel. `Channel#empty?` blocks
    # forever on an empty channel, so it cannot be used to ask whether work is
    # outstanding
    @pending_deletes = Atomic(Int32).new(0)

    # Queues removal of whatever is retained for the message's key
    def queue_delete(message : Message) : Nil
      queue_deletion(Deletion.new(message: message))
    end

    # Queues removal of whatever is retained under `topic`
    def queue_delete_topic(topic : String) : Nil
      queue_deletion(Deletion.new(topic: topic))
    end

    private def queue_deletion(deletion : Deletion) : Nil
      @pending_deletes.add(1)
      message_queue.send(deletion)
    end

    abstract def publish(message : Message)

    # Removes whatever is retained for the message's key.
    # Only meaningful where the destination retains state, so it does nothing
    # by default
    def delete(message : Message) : Nil
    end

    # Removes whatever is retained under `topic`. Nothing by default, as above
    def delete_topic(topic : String) : Nil
    end

    def commit : Nil
    end

    # Whether every queued deletion has been dealt with. A state resync waits
    # on this, so it cannot republish a key that is about to be removed
    def deletes_pending? : Bool
      @pending_deletes.get > 0
    end

    def start
      spawn { consume_messages }
    end

    def stop
      message_queue.close
    end

    private def consume_messages
      while !message_queue.closed?
        select
        when item = message_queue.receive?
          case item
          in Message
            begin
              publish(item)
              @processed += 1_u64
            rescue error
              Log.warn(exception: error) { "publishing message: #{item}" }
            end
          in Deletion
            handle_deletion(item)
          in Nil
          end
        when timeout(10.seconds)
          # commit any buffered messages that have not been published yet
          commit
        end
      end
    end

    private def handle_deletion(deletion : Deletion) : Nil
      if message = deletion.message
        delete(message)
      elsif topic = deletion.topic
        delete_topic(topic)
      end
      @deleted += 1_u64
    rescue error
      Log.warn(exception: error) { "deleting retained message: #{deletion}" }
    ensure
      @pending_deletes.sub(1)
    end
  end
end
