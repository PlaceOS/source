require "../spec_helper"

module PlaceOS::Source
  # Records the order work was done in, so the queue's guarantees can be
  # asserted without a broker in the way
  private class RecordingPublisher < Publisher
    getter handled : Array(String) = [] of String

    def publish(message : Publisher::Message)
      handled << "publish:#{message.payload}"
    end

    def delete(message : Publisher::Message)
      handled << "delete:#{message.payload}"
    end

    def delete_topic(topic : String)
      handled << "delete-topic:#{topic}"
    end
  end

  describe Publisher do
    # One queue for both, so a deletion can never overtake a stale value
    # queued before it, nor be overtaken by a value queued after it
    it "works through publications and deletions in the order they were queued" do
      publisher = RecordingPublisher.new
      event = Mappings::Metadata.new("mod-1234", "hello")

      publisher.message_queue.send(Publisher::Message.new(event, "message-0", Time.utc))
      publisher.queue_delete(Publisher::Message.new(event, "deletion-0", Time.utc))
      publisher.message_queue.send(Publisher::Message.new(event, "message-1", Time.utc))
      publisher.queue_delete_topic("placeos/org/state/stale")

      publisher.start
      sleep 200.milliseconds

      publisher.handled.should eq [
        "publish:message-0",
        "delete:deletion-0",
        "publish:message-1",
        "delete-topic:placeos/org/state/stale",
      ]
      publisher.deleted.should eq 2
      publisher.processed.should eq 2
      publisher.stop
    end

    it "reports whether deletions are still queued" do
      publisher = RecordingPublisher.new
      event = Mappings::Metadata.new("mod-1234", "hello")

      publisher.deletes_pending?.should be_false
      publisher.queue_delete(Publisher::Message.new(event, "pending", Time.utc))
      publisher.deletes_pending?.should be_true

      publisher.start
      sleep 200.milliseconds
      publisher.deletes_pending?.should be_false
      publisher.stop
    end

    # a consumer must notice a closed queue rather than spinning on it
    it "stops cleanly once the queue is closed" do
      publisher = RecordingPublisher.new
      publisher.start
      sleep 50.milliseconds

      done = Channel(Nil).new(1)
      spawn do
        publisher.stop
        done.send(nil)
      end

      select
      when done.receive
        publisher.message_queue.closed?.should be_true
      when timeout(5.seconds)
        fail "stop did not return"
      end
    end
  end
end
