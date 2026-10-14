require "./mappings"

module PlaceOS::Source
  # What is retained on the brokers right now, per Module.
  #
  # Recorded as each status is published or removed, so it is known what to
  # take away when a topic stops applying. It does not depend on the Module's
  # stored state or on the mappings, both of which may already have changed by
  # the time a change reaches us: a destroyed Module's storage is cleared by
  # core, and its system may drop it from the mappings before the Module's own
  # delete event arrives. Working the old topics out from either of those was
  # best effort, and lost them.
  class Published
    private getter lock = Mutex.new

    # module_id => statuses published for it, one per system it is mapped in
    private getter events = Hash(String, Set(Mappings::Status)).new

    def add(event : Mappings::Status) : Nil
      lock.synchronize do
        (events[event.module_id] ||= Set(Mappings::Status).new) << event
      end
    end

    def remove(event : Mappings::Status) : Nil
      lock.synchronize do
        if set = events[event.module_id]?
          set.delete(event)
          events.delete(event.module_id) if set.empty?
        end
      end
    end

    def for_module(module_id : String) : Set(Mappings::Status)
      lock.synchronize { events[module_id]?.try(&.dup) || Set(Mappings::Status).new }
    end

    # Modules with anything published that matches the block
    def module_ids(& : Mappings::Status -> Bool) : Set(String)
      lock.synchronize do
        events.each_with_object(Set(String).new) do |(module_id, set), ids|
          ids << module_id if set.any? { |event| yield event }
        end
      end
    end

    # Every event published, for comparing with what a broker holds
    def all : Array(Mappings::Status)
      lock.synchronize { events.values.flat_map(&.to_a) }
    end
  end
end
