require "test_helper"

class CoachStatusChangeTest < ActiveSupport::TestCase
  setup do
    @coach = Coach.create!(full_name: "A", phone: "+201000000001", password_hash: "h", status: "approved")
    @admin = AdminUser.create!(email: "t@c.app", name: "T", password: "Secret123")
  end

  test "persists and reloads a status change row" do
    change = CoachStatusChange.create!(
      coach: @coach,
      admin_user: @admin,
      from_status: "pending_review",
      to_status: "approved",
      reason: "Looks good"
    )
    reloaded = CoachStatusChange.find(change.id)
    assert_equal "pending_review", reloaded.from_status
    assert_equal "approved", reloaded.to_status
    assert_equal "Looks good", reloaded.reason
  end

  test "associations return the right records" do
    change = CoachStatusChange.create!(
      coach: @coach,
      admin_user: @admin,
      from_status: "pending_review",
      to_status: "approved",
      reason: "All docs verified"
    )
    assert_equal @coach, change.coach
    assert_equal @admin, change.admin_user
  end

  test "reason and commission_percent may be nil (approve-style row)" do
    change = CoachStatusChange.create!(
      coach: @coach,
      admin_user: @admin,
      from_status: "pending_review",
      to_status: "approved"
    )
    assert_nil change.reason
    assert_nil change.commission_percent
  end
end
