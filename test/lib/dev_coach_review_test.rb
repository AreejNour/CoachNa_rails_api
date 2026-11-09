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
