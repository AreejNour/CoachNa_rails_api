require "test_helper"

class CoachApp::RefreshTokensTest < ActiveSupport::TestCase
  def coach
    @coach ||= Coach.create!(phone: "+201012345670", password_hash: "x", full_name: "Rania")
  end

  def digest(token) = Digest::SHA256.hexdigest(token)

  test "issue returns 32 random bytes in base64url" do
    token = CoachApp::RefreshTokens.issue(coach.id)

    assert_match(/\A[A-Za-z0-9_-]{43}\z/, token)
    assert_not_equal token, CoachApp::RefreshTokens.issue(coach.id)
  end

  test "issue stores the SHA-256 hex digest, not the token" do
    token = CoachApp::RefreshTokens.issue(coach.id)

    assert CoachRefreshToken.exists?(coach_id: coach.id, token: digest(token))
    assert_not CoachRefreshToken.exists?(token: token)
  end

  test "issue expires in 30 days" do
    token = CoachApp::RefreshTokens.issue(coach.id)

    assert_in_delta 30.days.from_now, CoachRefreshToken.find_by!(token: digest(token)).expires_at, 5.seconds
  end

  test "rotate returns the owner once, then nil" do
    token = CoachApp::RefreshTokens.issue(coach.id)

    assert_equal coach.id, CoachApp::RefreshTokens.rotate(token)
    assert_nil CoachApp::RefreshTokens.rotate(token)
  end

  test "rotate accepts a token Node stored" do
    CoachRefreshToken.create!(coach: coach, token: digest("issued-by-node"), expires_at: 1.day.from_now)

    assert_equal coach.id, CoachApp::RefreshTokens.rotate("issued-by-node")
  end

  test "rotate refuses an expired token" do
    CoachRefreshToken.create!(coach: coach, token: digest("old"), expires_at: 1.minute.ago)

    assert_nil CoachApp::RefreshTokens.rotate("old")
  end

  test "rotate refuses an unknown token and input that is not a string" do
    assert_nil CoachApp::RefreshTokens.rotate("unknown")
    assert_nil CoachApp::RefreshTokens.rotate(nil)
    assert_nil CoachApp::RefreshTokens.rotate([ "unknown" ])
  end

  test "revoke deletes the token" do
    token = CoachApp::RefreshTokens.issue(coach.id)

    assert_nil CoachApp::RefreshTokens.revoke(token)
    assert_nil CoachApp::RefreshTokens.rotate(token)
  end

  test "revoke ignores an unknown token and input that is not a string" do
    assert_nil CoachApp::RefreshTokens.revoke("unknown")
    assert_nil CoachApp::RefreshTokens.revoke(nil)
  end

  test "revoke leaves the coach's other tokens alone" do
    first = CoachApp::RefreshTokens.issue(coach.id)
    second = CoachApp::RefreshTokens.issue(coach.id)

    CoachApp::RefreshTokens.revoke(first)

    assert_equal coach.id, CoachApp::RefreshTokens.rotate(second)
  end
end

class CoachApp::RefreshTokensConcurrencyTest < ActiveSupport::TestCase
  # Each thread needs its own committed view of the row.
  self.use_transactional_tests = false

  teardown { Coach.where(phone: "+201012345671").delete_all }

  test "two simultaneous rotations of one token: exactly one wins" do
    coach = Coach.create!(phone: "+201012345671", password_hash: "x", full_name: "Karim")

    10.times do
      token = CoachApp::RefreshTokens.issue(coach.id)
      start = Concurrent::CountDownLatch.new(1)
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.wait
            CoachApp::RefreshTokens.rotate(token)
          end
        end
      end
      start.count_down

      assert_equal [ coach.id ], threads.map(&:value).compact
    end
  end
end
