require "test_helper"

class CoachApp::OtpTest < ActiveSupport::TestCase
  PHONE = "+201012345672"

  def rows = PhoneVerification.where(phone: PHONE, account_type: "coach")

  def add_row(**attributes)
    PhoneVerification.create!({
      phone: PHONE, account_type: "coach", code_hash: Digest::SHA256.hexdigest("123456"),
      expires_at: 5.minutes.from_now, created_at: 10.minutes.ago
    }.merge(attributes))
  end

  def assert_api_error(status, message)
    error = assert_raises(ApiError) { yield }
    assert_equal [ status, message ], [ error.status, error.message ]
  end

  test "create returns a six digit code that expires in five minutes" do
    result = CoachApp::Otp.create(PHONE)

    assert_match(/\A\d{6}\z/, result[:code])
    assert_equal 300, result[:expires_in_seconds]
    assert_in_delta 5.minutes.from_now, rows.first.expires_at, 5.seconds
  end

  test "create stores the SHA-256 hex digest of the code, as a coach's" do
    result = CoachApp::Otp.create(PHONE)

    assert_equal Digest::SHA256.hexdigest(result[:code]), rows.first.code_hash
    assert_equal "signup", rows.first.purpose
  end

  test "a second request inside 60 seconds is a cooldown" do
    add_row(created_at: 59.seconds.ago)

    assert_api_error(429, "otp cooldown, try again shortly") { CoachApp::Otp.create(PHONE) }
  end

  test "a request after 60 seconds is allowed" do
    add_row(created_at: 61.seconds.ago)

    assert_nothing_raised { CoachApp::Otp.create(PHONE) }
  end

  test "a sixth request in an hour is refused" do
    5.times { |n| add_row(created_at: (n + 2).minutes.ago) }

    assert_api_error(429, "too many otp requests, try again later") { CoachApp::Otp.create(PHONE) }
  end

  test "requests older than an hour don't count" do
    4.times { |n| add_row(created_at: (n + 2).minutes.ago) }
    add_row(created_at: 61.minutes.ago)

    assert_nothing_raised { CoachApp::Otp.create(PHONE) }
  end

  test "a new code supersedes the previous unconsumed one" do
    old = add_row

    CoachApp::Otp.create(PHONE)

    assert_not_nil old.reload.consumed_at
  end

  test "a client's codes for the same phone are ignored and untouched" do
    client_row = add_row(account_type: "client", created_at: 1.second.ago)

    assert_nothing_raised { CoachApp::Otp.create(PHONE) }
    assert_nil client_row.reload.consumed_at
  end

  test "a client's code can't verify a coach sign-up" do
    add_row(account_type: "client")

    assert_api_error(400, "otp expired") { CoachApp::Otp.verify_and_consume(PHONE, "123456") { :ok } }
  end

  test "verify_and_consume consumes the code and returns the block's value" do
    row = add_row

    assert_equal :ok, CoachApp::Otp.verify_and_consume(PHONE, "123456") { :ok }
    assert_not_nil row.reload.consumed_at
  end

  test "a consumed code can't be used twice" do
    add_row
    CoachApp::Otp.verify_and_consume(PHONE, "123456") { :ok }

    assert_api_error(400, "otp expired") { CoachApp::Otp.verify_and_consume(PHONE, "123456") { :ok } }
  end

  test "an expired code is refused" do
    add_row(expires_at: 1.second.ago)

    assert_api_error(400, "otp expired") { CoachApp::Otp.verify_and_consume(PHONE, "123456") { :ok } }
  end

  test "a wrong code doesn't run the block, and the attempt is saved" do
    row = add_row
    ran = false

    assert_api_error(400, "invalid code") { CoachApp::Otp.verify_and_consume(PHONE, "000000") { ran = true } }

    assert_not ran
    assert_equal 1, row.reload.attempts
  end

  test "the fifth wrong code locks the code, even for the correct one" do
    add_row

    4.times { assert_api_error(400, "invalid code") { CoachApp::Otp.verify_and_consume(PHONE, "000000") { :ok } } }
    assert_api_error(400, "too many attempts") { CoachApp::Otp.verify_and_consume(PHONE, "000000") { :ok } }
    assert_api_error(400, "too many attempts") { CoachApp::Otp.verify_and_consume(PHONE, "123456") { :ok } }
  end

  test "if the block fails the code stays usable" do
    row = add_row

    assert_raises(RuntimeError) { CoachApp::Otp.verify_and_consume(PHONE, "123456") { raise "insert failed" } }

    assert_nil row.reload.consumed_at
    assert_equal :ok, CoachApp::Otp.verify_and_consume(PHONE, "123456") { :ok }
  end

  test "the limits come from the same settings as Node's" do
    original = ENV["OTP_LENGTH"]
    ENV["OTP_LENGTH"] = "4"

    assert_match(/\A\d{4}\z/, CoachApp::Otp.create(PHONE)[:code])
  ensure
    ENV["OTP_LENGTH"] = original
  end
end

class CoachApp::OtpCommitTest < ActiveSupport::TestCase
  # Outside a test transaction, so this proves the attempt really reaches the database.
  self.use_transactional_tests = false

  PHONE = "+201012345673"

  teardown { PhoneVerification.where(phone: PHONE).delete_all }

  test "a wrong code's attempt is committed" do
    row = PhoneVerification.create!(phone: PHONE, code_hash: Digest::SHA256.hexdigest("123456"), expires_at: 5.minutes.from_now)

    assert_raises(ApiError) { CoachApp::Otp.verify_and_consume(PHONE, "000000") { :ok } }

    seen = Thread.new { ActiveRecord::Base.connection_pool.with_connection { PhoneVerification.find(row.id).attempts } }.value
    assert_equal 1, seen
  end

  test "simultaneous wrong codes can't share an attempt" do
    row = PhoneVerification.create!(phone: PHONE, code_hash: Digest::SHA256.hexdigest("123456"), expires_at: 5.minutes.from_now)

    threads = 4.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          CoachApp::Otp.verify_and_consume(PHONE, "000000") { :ok }
        rescue ApiError
          nil
        end
      end
    end
    threads.each(&:join)

    assert_equal 4, row.reload.attempts
  end
end
