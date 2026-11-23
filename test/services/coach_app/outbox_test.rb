require "test_helper"

class CoachApp::OutboxTest < ActiveSupport::TestCase
  setup { CoachApp::QueuePublisher.adapter = CoachApp::QueuePublisher::TestAdapter.new }
  teardown { CoachApp::QueuePublisher.adapter = nil }

  def publisher = CoachApp::QueuePublisher.adapter

  test "enqueue inside a rolled-back transaction leaves no row" do
    ActiveRecord::Base.transaction do
      CoachApp::Outbox.enqueue!(kind: "push", payload: { a: 1 })
      raise ActiveRecord::Rollback
    end

    assert_equal 0, OutboxMessage.count
  end

  test "enqueue returns the id of an unpublished row" do
    id = CoachApp::Outbox.enqueue!(kind: "email", payload: { to: "a@b.co" })

    row = OutboxMessage.find(id)
    assert_equal "email", row.kind
    assert_equal({ "to" => "a@b.co" }, row.payload)
    assert_nil row.published_at
    assert_empty publisher.published
  end

  test "publish_after_commit publishes the id on the kind's routing key and stamps the row" do
    push = CoachApp::Outbox.enqueue!(kind: "push", payload: {})
    email = CoachApp::Outbox.enqueue!(kind: "email", payload: {})

    CoachApp::Outbox.publish_after_commit([ push, email ])

    assert_equal [
      { exchange: "coachna", routing_key: "push", body: { outboxId: push }.to_json },
      { exchange: "coachna", routing_key: "email", body: { outboxId: email }.to_json }
    ].sort_by { |m| m[:routing_key] }, publisher.published.sort_by { |m| m[:routing_key] }
    assert_not_nil OutboxMessage.find(push).published_at
    assert_not_nil OutboxMessage.find(email).published_at
  end

  test "a raising publisher leaves the row unpublished and does not raise" do
    publisher.fail_with = RuntimeError.new("broker down")
    id = CoachApp::Outbox.enqueue!(kind: "push", payload: {})

    assert_nothing_raised { CoachApp::Outbox.publish_after_commit([ id ]) }
    assert_nil OutboxMessage.find(id).published_at
  end

  test "one failed publish does not stop the others" do
    first = CoachApp::Outbox.enqueue!(kind: "push", payload: {})
    second = CoachApp::Outbox.enqueue!(kind: "push", payload: {})
    publisher.fail_with = RuntimeError.new("down")
    publisher.fail_times = 1

    CoachApp::Outbox.publish_after_commit([ first, second ])

    assert_equal 1, OutboxMessage.where(id: [ first, second ], published_at: nil).count
    assert_equal 1, publisher.published.size
  end

  test "an unknown or empty id list is ignored" do
    assert_nothing_raised do
      CoachApp::Outbox.publish_after_commit([])
      CoachApp::Outbox.publish_after_commit([ SecureRandom.uuid ])
    end
    assert_empty publisher.published
  end
end
