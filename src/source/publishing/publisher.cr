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

    # Keys whose retained value has to be removed, because the topic they were
    # published under no longer exists — a renamed or reindexed Module, or one
    # that was destroyed.
    #
    # NOTE:: this is drained ahead of `message_queue`. A rename removes the old
    # topic and republishes under the new one, and if the publish were to win
    # the race the delete would take the new value straight back out again
    getter delete_queue : Channel(Message) = Channel(Message).new(StatusEvents::BATCH_SIZE)

    getter processed : UInt64 = 0_u64
    getter deleted : UInt64 = 0_u64

    abstract def publish(message : Message)

    # Removes whatever is retained for the message's key.
    # Only meaningful where the destination retains state, so it does nothing
    # by default
    def delete(message : Message) : Nil
    end

    def commit : Nil
    end

    # Whether every queued deletion has been dealt with. A state resync waits
    # on this, so it cannot republish a key that is about to be removed
    def deletes_pending? : Bool
      !delete_queue.empty?
    end

    def start
      spawn { consume_messages }
    end

    def stop
      message_queue.close
      delete_queue.close
    end

    private def consume_messages
      while !message_queue.closed?
        # deletions first, always, and keep going while any remain
        next if drain_deletion

        select
        when message = message_queue.receive?
          if message
            begin
              publish(message)
              @processed += 1_u64
            rescue error
              Log.warn(exception: error) { "publishing message: #{message}" }
            end
          end
        when deletion = delete_queue.receive?
          handle_deletion(deletion) if deletion
        when timeout(10.seconds)
          # commit any buffered messages that have not been published yet
          commit
        end
      end
    end

    # Takes a deletion without blocking, so a pending one always goes first.
    #
    # NOTE:: a closed channel yields nil from `receive?` immediately, so this
    # has to report "nothing taken" for it — otherwise the caller spins on a
    # closed queue instead of noticing it should stop
    private def drain_deletion : Bool
      return false if delete_queue.closed?

      select
      when deletion = delete_queue.receive?
        return false if deletion.nil?
        handle_deletion(deletion)
        true
      else
        false
      end
    end

    private def handle_deletion(message : Message) : Nil
      delete(message)
      @deleted += 1_u64
    rescue error
      Log.warn(exception: error) { "deleting retained message: #{message}" }
    end
  end
end
