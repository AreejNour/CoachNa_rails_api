require "test_helper"

class CoachTest < ActiveSupport::TestCase
  test "a new coach gets its id, status and specialties from the database defaults" do
    coach = Coach.create!(phone: "+201012345678", password_hash: "x", full_name: "Rania").reload

    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, coach.id)
    assert_equal "incomplete", coach.status
    assert_equal [], coach.specialties
  end

  test "SPECIALTIES is the fixed list the client app translates" do
    assert_equal %w[weight_loss muscle_gain diabetes_friendly sports womens_health general], Coach::SPECIALTIES
  end

  test "EDITABLE_STATUSES are incomplete and rejected" do
    assert_equal %w[incomplete rejected], Coach::EDITABLE_STATUSES
  end

  test "a refresh token belongs to its coach" do
    coach = Coach.create!(phone: "+201012345679", password_hash: "x", full_name: "Karim")

    token = CoachRefreshToken.create!(coach: coach, token: "digest", expires_at: 1.day.from_now)

    assert_equal coach, token.reload.coach
  end

  test "a phone verification reads the shared table with its defaults" do
    verification = PhoneVerification.create!(phone: "+201012345678", code_hash: "digest", expires_at: 5.minutes.from_now).reload

    assert_equal 0, verification.attempts
    assert_equal "coach", verification.account_type
    assert_equal "signup", verification.purpose
  end
end
