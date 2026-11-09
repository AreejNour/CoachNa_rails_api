require "test_helper"

class CoachApp::SignupsControllerTest < ActionDispatch::IntegrationTest
  LOCAL = "01012345674"
  E164 = "+201012345674"
  PASSWORD = "Demo@12345"

  def request_otp(phone: LOCAL, country: "EG")
    post "/coach/auth/signup/request-otp", params: { phone: phone, country: country }, as: :json
  end

  def verify(**overrides)
    post "/coach/auth/signup/verify", as: :json, params: {
      phone: LOCAL, country: "EG", code: "123456", password: PASSWORD, fullName: "Rania Adel"
    }.merge(overrides)
  end

  def add_code(code: "123456", phone: E164, **attributes)
    PhoneVerification.create!({
      phone: phone, account_type: "coach", code_hash: Digest::SHA256.hexdigest(code), expires_at: 5.minutes.from_now
    }.merge(attributes))
  end

  def assert_failure(status, message)
    assert_response status
    assert_equal({ "success" => false, "error" => message }, response.parsed_body)
  end

  def data = response.parsed_body["data"]

  # --- request-otp

  test "request-otp returns the expiry and, outside production, the code" do
    request_otp

    assert_response :ok
    assert_equal 300, data["expiresInSeconds"]
    assert_match(/\A\d{6}\z/, data["devCode"])
    assert PhoneVerification.exists?(phone: E164, account_type: "coach")
  end

  test "request-otp never returns the code in production" do
    Rails.env = "production"
    request_otp

    assert_response :ok
    assert_not data.key?("devCode")
  ensure
    Rails.env = "test"
  end

  test "request-otp hands the code to the sender" do
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)
    request_otp

    assert_includes log.string, "[otp] code for #{E164}: #{data["devCode"]}"
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  test "request-otp accepts Arabic digits" do
    request_otp(phone: "٠١٠١٢٣٤٥٦٧٤")

    assert_response :ok
    assert PhoneVerification.exists?(phone: E164)
  end

  test "request-otp refuses an invalid phone" do
    request_otp(phone: "123")

    assert_failure :bad_request, "invalid phone"
  end

  test "request-otp refuses a registered phone" do
    Coach.create!(phone: E164, password_hash: "x", full_name: "Taken")
    request_otp

    assert_failure :conflict, "phone already registered"
  end

  test "request-otp reports the cooldown" do
    request_otp
    request_otp

    assert_failure :too_many_requests, "otp cooldown, try again shortly"
  end

  test "request-otp refuses an unsupported country, a lowercase one and a missing one" do
    [ "XX", "eg", nil, 20 ].each do |country|
      request_otp(country: country)

      assert_failure :bad_request, "validation failed"
    end
  end

  test "request-otp refuses a phone that isn't a non-empty string" do
    [ 1012345674, [ LOCAL ], { a: 1 }, "", nil, "0101\u000012345" ].each do |phone|
      request_otp(phone: phone)

      assert_failure :bad_request, "validation failed"
    end
  end

  test "malformed JSON is 400 validation failed" do
    post "/coach/auth/signup/request-otp", params: "{bad", headers: { "CONTENT_TYPE" => "application/json" }

    assert_failure :bad_request, "validation failed"
  end

  # --- countries

  test "countries returns the list in the envelope, with no sign-in" do
    get "/coach/auth/countries"

    assert_response :ok
    assert_includes data, { "country" => "EG", "callingCode" => "20" }
  end

  # --- check-otp

  def check_otp(**overrides)
    post "/coach/auth/signup/check-otp", as: :json, params: { phone: LOCAL, country: "EG", code: "123456" }.merge(overrides)
  end

  test "check-otp accepts the right code without using it, and verify then accepts it" do
    row = add_code
    check_otp

    assert_response :ok
    assert_equal({ "success" => true, "data" => {} }, response.parsed_body)
    assert_nil row.reload.consumed_at
    assert_not Coach.exists?(phone: E164)

    verify
    assert_response :created
  end

  test "check-otp accepts Arabic digits" do
    add_code
    check_otp(code: "١٢٣٤٥٦")

    assert_response :ok
  end

  test "a wrong code at check-otp counts as an attempt that verify shares" do
    row = add_code
    check_otp(code: "000000")
    assert_failure :bad_request, "invalid code"
    assert_equal 1, row.reload.attempts

    verify(code: "000000")
    assert_equal 2, row.reload.attempts
  end

  test "the fifth wrong code at check-otp locks it" do
    add_code
    4.times { check_otp(code: "000000") }
    check_otp(code: "000000")
    assert_failure :bad_request, "too many attempts"

    check_otp
    assert_failure :bad_request, "too many attempts"
  end

  test "check-otp reports an expired code" do
    add_code(expires_at: 1.second.ago)
    check_otp

    assert_failure :bad_request, "otp expired"
  end

  test "check-otp reports a registered phone" do
    Coach.create!(phone: E164, password_hash: "x", full_name: "Taken")
    add_code
    check_otp

    assert_failure :conflict, "phone already registered"
  end

  test "check-otp refuses an invalid phone and bad fields" do
    check_otp(phone: "123")
    assert_failure :bad_request, "invalid phone"

    [ { code: nil }, { code: "" }, { code: 123456 }, { phone: nil }, { country: "XX" } ].each do |fields|
      check_otp(**fields)
      assert_failure :bad_request, "validation failed"
    end
  end

  # --- verify

  test "verify creates the coach and returns the contract's fields" do
    add_code
    verify(email: "rania@example.com")

    assert_response :created
    coach = Coach.find_by!(phone: E164)
    assert_equal "incomplete", coach.status
    assert_not_nil coach.phone_verified_at
    assert CoachApp::Password.verify(PASSWORD, coach.password_hash)
    assert_equal({
      "id" => coach.id, "phone" => E164, "email" => "rania@example.com", "fullName" => "Rania Adel", "bio" => nil,
      "yearsExperience" => nil, "specialties" => [], "status" => "incomplete", "rejectionReason" => nil,
      "phoneVerifiedAt" => coach.phone_verified_at.iso8601(3), "profileSubmittedAt" => nil
    }, data["coach"])
  end

  test "verify returns tokens that work" do
    add_code
    verify

    coach_id = data["coach"]["id"]
    assert_equal coach_id, CoachApp::AccessToken.verify(data["accessToken"])
    assert_equal coach_id, CoachApp::RefreshTokens.rotate(data["refreshToken"])
  end

  test "the response never contains the password hash or commission" do
    add_code
    verify

    assert_response :created
    assert_no_match(/passwordHash|password_hash|commission|\$2a\$/, response.body)
  end

  test "verify trims the full name and leaves email out when absent" do
    add_code
    verify(fullName: "  Rania  ")

    assert_equal "Rania", data["coach"]["fullName"]
    assert_nil data["coach"]["email"]
  end

  test "a code typed in Arabic digits verifies" do
    add_code
    verify(code: "١٢٣٤٥٦")

    assert_response :created
  end

  test "an Arabic password and name work" do
    add_code
    verify(password: "كلمةسر١٢٣٤٥", fullName: "رانيا عادل")

    assert_response :created
    assert CoachApp::Password.verify("كلمةسر١٢٣٤٥", Coach.find_by!(phone: E164).password_hash)
    assert_equal "رانيا عادل", data["coach"]["fullName"]
  end

  test "a wrong code is refused and counted, and no coach is created" do
    row = add_code
    verify(code: "000000")

    assert_failure :bad_request, "invalid code"
    assert_equal 1, row.reload.attempts
    assert_not Coach.exists?(phone: E164)
  end

  test "the fifth wrong code locks it, and the correct code then fails too" do
    add_code
    4.times { verify(code: "000000") }
    verify(code: "000000")
    assert_failure :bad_request, "too many attempts"

    verify
    assert_failure :bad_request, "too many attempts"
  end

  test "an expired code is refused" do
    add_code(expires_at: 1.second.ago)
    verify

    assert_failure :bad_request, "otp expired"
  end

  test "a code for another phone is refused" do
    add_code(phone: "+201012345675")
    verify

    assert_failure :bad_request, "otp expired"
  end

  test "an invalid phone is refused" do
    verify(phone: "123")

    assert_failure :bad_request, "invalid phone"
  end

  test "a registered phone is refused" do
    Coach.create!(phone: E164, password_hash: "x", full_name: "Taken")
    add_code
    verify

    assert_failure :conflict, "phone already registered"
  end

  test "a taken email is 409, creates nobody, and the code still works with another email" do
    Coach.create!(phone: "+201012345676", email: "taken@example.com", password_hash: "x", full_name: "Taken")
    add_code
    verify(email: "taken@example.com")

    assert_failure :conflict, "email already registered"
    assert_not Coach.exists?(phone: E164)

    verify(email: "free@example.com")
    assert_response :created
  end

  test "a wrong code doesn't reveal whether an email is taken" do
    Coach.create!(phone: "+201012345676", email: "taken@example.com", password_hash: "x", full_name: "Taken")
    add_code
    verify(code: "000000", email: "taken@example.com")

    assert_failure :bad_request, "invalid code"
  end

  test "a phone already used by a client can still sign up as a coach" do
    ActiveRecord::Base.connection.execute(
      "INSERT INTO clients (phone, password_hash, full_name) VALUES ('#{E164}', 'x', 'Client')"
    )
    add_code
    verify

    assert_response :created
  end

  test "a password of 7 characters is refused and 8 is accepted" do
    add_code
    verify(password: "1234567")
    assert_failure :bad_request, "validation failed"

    verify(password: "12345678")
    assert_response :created
  end

  test "bad fields are refused with validation failed and leave the code unused" do
    row = add_code
    [
      { fullName: "" }, { fullName: "   " }, { fullName: nil }, { fullName: 5 }, { fullName: "a" * 101 },
      { fullName: "Ra\u0000nia" }, { password: nil }, { password: 12345678 }, { password: "Demo@12345\u0000x" },
      { code: "" }, { code: nil }, { code: 123456 }, { email: "not-an-email" }, { email: "" }, { email: 5 },
      { email: "a\u0000@example.com" }, { country: "XX" }
    ].each do |fields|
      verify(**fields)

      assert_failure :bad_request, "validation failed"
    end

    assert_nil row.reload.consumed_at
    assert_equal 0, row.attempts
  end

  test "a body with protected fields can't set them" do
    add_code
    verify(status: "approved", commissionPercent: 1, averageRating: 5)

    assert_response :created
    coach = Coach.find_by!(phone: E164)
    assert_equal "incomplete", coach.status
    assert_nil coach.commission_percent
    assert_nil coach.average_rating
  end
end

class CoachApp::SignupConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  PHONE = "01012345677"
  E164 = "+201012345677"

  teardown do
    Coach.where(phone: E164).delete_all
    PhoneVerification.where(phone: E164).delete_all
  end

  test "two simultaneous verifies give one coach and one clean refusal" do
    PhoneVerification.create!(phone: E164, code_hash: Digest::SHA256.hexdigest("123456"), expires_at: 5.minutes.from_now)
    start = Concurrent::CountDownLatch.new(1)

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.wait
          CoachApp::Signup.verify(phone: PHONE, country: "EG", code: "123456", password: "Demo@12345", full_name: "Rania", email: nil)
          :created
        rescue ApiError => error
          error.status
        end
      end
    end
    start.count_down
    results = threads.map(&:value)

    assert_equal 1, results.count(:created), results.inspect
    assert_includes [ 400, 409 ], (results - [ :created ]).first
    assert_equal 1, Coach.where(phone: E164).count
  end
end
