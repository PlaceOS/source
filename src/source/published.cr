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

    # control_system_id => module_id => how many of its statuses are there.
    # So a system can be looked up without scanning everything published
    private getter by_system = Hash(String, Hash(String, Int32)).new

    def add(event : Mappings::Status) : Nil
      lock.synchronize do
        set = events[event.module_id] ||= Set(Mappings::Status).new
        next if set.includes?(event)
        set << event
        counts = by_system[event.control_system_id] ||= Hash(String, Int32).new(0)
        counts[event.module_id] += 1
      end
    end

    def remove(event : Mappings::Status) : Nil
      lock.synchronize do
        next unless set = events[event.module_id]?
        next unless set.delete(event)
        events.delete(event.module_id) if set.empty?

        next unless counts = by_system[event.control_system_id]?
        if (counts[event.module_id] -= 1) <= 0
          counts.delete(event.module_id)
          by_system.delete(event.control_system_id) if counts.empty?
        end
      end
    end

    # Forget everything, once nothing is retained any more
    def clear : Nil
      lock.synchronize do
        events.clear
        by_system.clear
      end
    end

    def for_module(module_id : String) : Set(Mappings::Status)
      lock.synchronize { events[module_id]?.try(&.dup) || Set(Mappings::Status).new }
    end

    # Modules with anything published in any of these systems
    def module_ids_in(control_system_ids : Enumerable(String)) : Set(String)
      lock.synchronize do
        control_system_ids.each_with_object(Set(String).new) do |control_system_id, ids|
          by_system[control_system_id]?.try &.each_key { |module_id| ids << module_id }
        end
      end
    end

    # Everything published in one system
    def for_system(control_system_id : String) : Array(Mappings::Status)
      lock.synchronize do
        found = [] of Mappings::Status
        by_system[control_system_id]?.try &.each_key do |module_id|
          events[module_id]?.try &.each { |event| found << event if event.control_system_id == control_system_id }
        end
        found
      end
    end
  end
end
