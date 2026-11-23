require "test_helper"

# Commits for real (no wrapping transaction) so a second connection can hold the worker's row lock.
class CoachApp::OutboxLockTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup { CoachApp::QueuePublisher.adapter = CoachApp::QueuePublisher::TestAdapter.new }

  teardown do
    CoachApp::QueuePublisher.adapter = nil
    OutboxMessage.delete_all
  end

  test "publish_after_commit does not wait on a row the worker has locked" do
    id = CoachApp::Outbox.enqueue!(kind: "push", payload: {})
    locked = Queue.new
    release = Queue.new

    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        OutboxMessage.transaction do
          OutboxMessage.lock("FOR UPDATE").find(id)
          locked << true
          release.pop
        end
      end
    end
    locked.pop

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    CoachApp::Outbox.publish_after_commit([ id ])
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    release << true
    worker.join

    assert_operator elapsed, :<, 1.0
    assert_nil OutboxMessage.find(id).published_at
  end
end
