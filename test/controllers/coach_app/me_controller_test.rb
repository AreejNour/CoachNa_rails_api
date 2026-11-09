require "test_helper"

class CoachApp::MeControllerTest < ActionDispatch::IntegrationTest
  setup { @coach = Coach.create!(phone: "+201012345682", password_hash: "x", full_name: "Karim") }

  def me(header) = get("/coach/me", headers: header ? { "Authorization" => header } : {})

  def bearer(token) = "Bearer #{token}"

  def claims(**overrides)
    now = Time.now.to_i
    { sub: @coach.id, type: "coach", iat: now, exp: now + 900 }.merge(overrides)
  end

  def secret = ENV.fetch("JWT_ACCESS_SECRET")

  def assert_unauthorized
    assert_response :unauthorized
    assert_equal({ "success" => false, "error" => "unauthorized" }, response.parsed_body)
  end

  test "returns the coach for a valid token" do
    me(bearer(CoachApp::AccessToken.sign(@coach.id)))

    assert_response :ok
    assert_equal @coach.id, response.parsed_body["data"]["coach"]["id"]
    assert_no_match(/password|commission/i, response.body)
  end

  test "refuses a missing header" do
    me(nil)

    assert_unauthorized
  end

  test "refuses a header that isn't Bearer" do
    me("Basic #{CoachApp::AccessToken.sign(@coach.id)}")

    assert_unauthorized
  end

  test "refuses an empty Bearer token" do
    me("Bearer ")

    assert_unauthorized
  end

  test "refuses an expired token" do
    me(bearer(JWT.encode(claims(exp: 1.minute.ago.to_i), secret, "HS256")))

    assert_unauthorized
  end

  test "refuses a client's token" do
    me(bearer(JWT.encode(claims(type: "client"), secret, "HS256")))

    assert_unauthorized
  end

  test "refuses a token for a coach who no longer exists" do
    token = CoachApp::AccessToken.sign(@coach.id)
    @coach.destroy!
    me(bearer(token))

    assert_unauthorized
  end

  test "refuses a token whose sub isn't a coach id" do
    me(bearer(CoachApp::AccessToken.sign("not-a-uuid")))

    assert_unauthorized
  end
end
