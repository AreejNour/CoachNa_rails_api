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

  test "EDITABLE_STATUSES is only incomplete (rejected is final)" do
    assert_equal %w[incomplete], Coach::EDITABLE_STATUSES
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

  test "GENDERS is male and female" do
    assert_equal %w[male female], Coach::GENDERS
  end

  test "gender and date of birth are optional" do
    assert Coach.new(phone: "+201012345601", password_hash: "x", full_name: "A").valid?
  end

  test "gender must be male or female" do
    coach = Coach.new(phone: "+201012345602", password_hash: "x", full_name: "A")
    coach.gender = "other"
    assert_not coach.valid?
    coach.gender = "female"
    assert coach.valid?
  end

  test "date of birth rules: future, before 1900 and under 18 are refused; turning 18 today is fine" do
    travel_to Date.new(2026, 11, 28) do
      coach = Coach.new(phone: "+201012345603", password_hash: "x", full_name: "A")
      {
        Date.new(2026, 11, 29) => false, Date.new(1899, 12, 31) => false, Date.new(1900, 1, 1) => true,
        Date.new(2008, 11, 29) => false, Date.new(2008, 11, 28) => true, Date.new(1990, 3, 12) => true
      }.each do |date, ok|
        coach.date_of_birth = date
        assert_equal ok, coach.valid?, date.to_s
      end
    end
  end

  test "age around birthdays and 29 Feb" do
    coach = Coach.new(date_of_birth: Date.new(1990, 3, 12))
    assert_equal 35, coach.age(Date.new(2026, 3, 11))
    assert_equal 36, coach.age(Date.new(2026, 3, 12))
    leap = Coach.new(date_of_birth: Date.new(2000, 2, 29))
    assert_equal 25, leap.age(Date.new(2026, 2, 28))
    assert_equal 26, leap.age(Date.new(2026, 3, 1))
    assert_equal 28, leap.age(Date.new(2028, 2, 29))
    assert_nil Coach.new.age
  end
end
