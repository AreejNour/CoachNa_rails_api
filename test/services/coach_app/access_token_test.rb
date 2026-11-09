require "test_helper"

class CoachApp::AccessTokenTest < ActiveSupport::TestCase
  COACH_ID = "8500c177-e93f-4e06-914a-bf3ab9190810"

  def secret = ENV.fetch("JWT_ACCESS_SECRET")

  def claims(**overrides)
    now = Time.now.to_i
    { sub: COACH_ID, type: "coach", iat: now, exp: now + 900 }.merge(overrides).compact
  end

  test "sign produces HS256 with exactly sub, type, iat and exp, lasting 15 minutes" do
    payload, header = JWT.decode(CoachApp::AccessToken.sign(COACH_ID), secret, true, algorithm: "HS256")

    assert_equal "HS256", header["alg"]
    assert_equal %w[exp iat sub type], payload.keys.sort
    assert_equal COACH_ID, payload["sub"]
    assert_equal "coach", payload["type"]
    assert_equal 900, payload["exp"] - payload["iat"]
  end

  test "verify returns the coach id of a token it signed" do
    assert_equal COACH_ID, CoachApp::AccessToken.verify(CoachApp::AccessToken.sign(COACH_ID))
  end

  test "verify returns the coach id of a token shaped like Node's" do
    assert_equal COACH_ID, CoachApp::AccessToken.verify(JWT.encode(claims, secret, "HS256"))
  end

  test "verify refuses an expired token" do
    assert_nil CoachApp::AccessToken.verify(JWT.encode(claims(exp: 1.minute.ago.to_i), secret, "HS256"))
  end

  test "verify refuses a token with no expiry" do
    assert_nil CoachApp::AccessToken.verify(JWT.encode(claims(exp: nil), secret, "HS256"))
  end

  test "verify refuses a token signed with another secret" do
    assert_nil CoachApp::AccessToken.verify(JWT.encode(claims, "another-secret", "HS256"))
  end

  test "verify refuses an unsigned token" do
    assert_nil CoachApp::AccessToken.verify(JWT.encode(claims, nil, "none"))
  end

  test "verify refuses another signing algorithm" do
    assert_nil CoachApp::AccessToken.verify(JWT.encode(claims, secret, "HS512"))
  end

  test "verify refuses a client's token" do
    assert_nil CoachApp::AccessToken.verify(JWT.encode(claims(type: "client"), secret, "HS256"))
  end

  test "verify refuses a sub that is not a string" do
    assert_nil CoachApp::AccessToken.verify(JWT.encode(claims(sub: 123), secret, "HS256"))
  end

  test "verify refuses garbage and nil" do
    assert_nil CoachApp::AccessToken.verify("not-a-token")
    assert_nil CoachApp::AccessToken.verify(nil)
  end

  test "an empty secret is refused rather than signed with" do
    original = ENV["JWT_ACCESS_SECRET"]
    ENV["JWT_ACCESS_SECRET"] = ""

    assert_raises(KeyError) { CoachApp::AccessToken.sign(COACH_ID) }
  ensure
    ENV["JWT_ACCESS_SECRET"] = original
  end
end
