require "test_helper"

class DevCoachReviewTest < ActiveSupport::TestCase
  PHONE = "+201012345712"

  setup { @coach = Coach.create!(phone: PHONE, password_hash: "x", full_name: "Sara", status: "pending_review") }

  test "approve moves pending_review to approved, with the commission" do
    @coach.update!(rejection_reason: "old")

    DevCoachReview.approve!(phone: PHONE, commission: "15")

    @coach.reload
    assert_equal [ "approved", 15, nil ], [ @coach.status, @coach.commission_percent, @coach.rejection_reason ]
    assert_not_nil @coach.reviewed_at
  end

  test "reject moves pending_review to rejected, with the reason" do
    DevCoachReview.reject!(phone: PHONE, reason: "Your certificate photo is too blurry to read.")

    @coach.reload
    assert_equal [ "rejected", "Your certificate photo is too blurry to read." ], [ @coach.status, @coach.rejection_reason ]
    assert_not_nil @coach.reviewed_at
  end

  test "approve enqueues the coach push and the approved email" do
    @coach.update!(email: "sara@example.com")

    DevCoachReview.approve!(phone: PHONE, commission: "15")

    push = OutboxMessage.find_by!(kind: "push").payload
    assert_equal({ "recipient" => { "type" => "coach", "id" => @coach.id },
                   "title" => { "ar" => "تمت الموافقة على حسابك", "en" => "You're approved" },
                   "body" => push["body"], "data" => { "screen" => "coach_home" } }, push)
    assert push["body"]["ar"].present? && push["body"]["en"].present?
    assert_equal({ "to" => "sara@example.com", "template" => "coach_application_approved",
                   "data" => { "firstName" => "Sara" } }, OutboxMessage.find_by!(kind: "email").payload)
  end

  test "reject enqueues the coach push and the needs-changes email with the reason" do
    @coach.update!(email: "sara@example.com")

    DevCoachReview.reject!(phone: PHONE, reason: "Blurry photo")

    push = OutboxMessage.find_by!(kind: "push").payload
    assert_equal({ "ar" => "طلبك يحتاج إلى تعديلات", "en" => "Your application needs changes" }, push["title"])
    assert_equal({ "screen" => "coach_needs_changes" }, push["data"])
    assert_equal({ "to" => "sara@example.com", "template" => "coach_application_needs_changes",
                   "data" => { "firstName" => "Sara", "reason" => "Blurry photo" } },
                 OutboxMessage.find_by!(kind: "email").payload)
  end

  test "a coach without an email still gets the push, and no email" do
    DevCoachReview.approve!(phone: PHONE, commission: "15")

    assert_equal 1, OutboxMessage.where(kind: "push").count
    assert_equal 0, OutboxMessage.where(kind: "email").count
  end

  test "a failure while enqueueing rolls back the review and every row" do
    @coach.update!(email: "sara@example.com")
    calls = 0
    original = CoachApp::Outbox.method(:enqueue_and_publish_after_commit!)
    swap_method(CoachApp::Outbox, :enqueue_and_publish_after_commit!, ->(**kw) { (calls += 1) == 2 ? raise("boom") : original.call(**kw) }) do
      assert_raises(RuntimeError) { DevCoachReview.approve!(phone: PHONE, commission: "15") }
    end
    assert_equal "pending_review", @coach.reload.status
    assert_equal 0, OutboxMessage.count
  end

  [ nil, "", "   " ].each do |reason|
    test "reject refuses the reason #{reason.inspect}" do
      assert_raises(DevCoachReview::Refused) { DevCoachReview.reject!(phone: PHONE, reason: reason) }
      assert_equal "pending_review", @coach.reload.status
    end
  end

  [ "-1", "101", "abc", "", nil ].each do |commission|
    test "approve refuses the commission #{commission.inspect}" do
      assert_raises(DevCoachReview::Refused) { DevCoachReview.approve!(phone: PHONE, commission: commission) }
      assert_equal "pending_review", @coach.reload.status
    end
  end

  %w[incomplete approved rejected suspended deactivated].each do |status|
    test "a coach who is #{status} is refused, and the message says why" do
      @coach.update!(status: status)

      error = assert_raises(DevCoachReview::Refused) { DevCoachReview.approve!(phone: PHONE, commission: "15") }

      assert_includes error.message, status
      assert_equal status, @coach.reload.status
    end
  end

  test "an unknown phone is refused" do
    assert_raises(DevCoachReview::Refused) { DevCoachReview.approve!(phone: "+201000000000", commission: "15") }
  end

  test "both refuse to run in production" do
    Rails.env = "production"

    assert_raises(DevCoachReview::Refused) { DevCoachReview.approve!(phone: PHONE, commission: "15") }
    assert_raises(DevCoachReview::Refused) { DevCoachReview.reject!(phone: PHONE, reason: "No") }
  ensure
    Rails.env = "test"
    assert_equal "pending_review", @coach.reload.status
  end
end
