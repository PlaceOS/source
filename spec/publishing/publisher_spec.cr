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
  end

  describe Publisher do
    # A rename removes the old topic and republishes under the new one. If a
    # publish were to win that race the delete would take the new value straight
    # back out, so deletions have to be drained first
    it "drains queued deletions before queued messages" do
      publisher = RecordingPublisher.new
      event = Mappings::Metadata.new("mod-1234", "hello")

      # queued messages first, deletions second — order of arrival must not
      # decide order of work
      3.times { |i| publisher.message_queue.send(Publisher::Message.new(event, "message-#{i}", Time.utc)) }
      2.times { |i| publisher.queue_delete(Publisher::Message.new(event, "deletion-#{i}", Time.utc)) }

      publisher.start
      sleep 200.milliseconds

      publisher.handled.first(2).should eq ["delete:deletion-0", "delete:deletion-1"]
      publisher.handled.size.should eq 5
      publisher.deleted.should eq 2
      publisher.processed.should eq 3
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
    it "stops cleanly once the queues are closed" do
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
        publisher.delete_queue.closed?.should be_true
      when timeout(5.seconds)
        fail "stop did not return"
      end
    end
  end
end
