require "test_helper"

class CoachApp::SessionsControllerTest < ActionDispatch::IntegrationTest
  # Hashed by bcryptjs in the Node API: a coach who signed up there logs in here.
  NODE_HASH = "$2a$12$gVjeJT.E1dAjYIbStBByCenFyH2u990j7idUMYXH14rsKJ0/xIc8S"
  PASSWORD = "Demo@12345"
  E164 = "+201012345680"

  setup { @coach = Coach.create!(phone: E164, password_hash: NODE_HASH, full_name: "Rania") }

  def login(phone: "01012345680", country: "EG", password: PASSWORD)
    post "/coach/auth/login", params: { phone: phone, country: country, password: password }, as: :json
  end

  def refresh(token) = post("/coach/auth/refresh", params: { refreshToken: token }, as: :json)
  def logout(token) = post("/coach/auth/logout", params: { refreshToken: token }, as: :json)
  def data = response.parsed_body["data"]

  def assert_failure(status, message)
    assert_response status
    assert_equal({ "success" => false, "error" => message }, response.parsed_body)
  end

  test "a coach with a Node password hash logs in and gets the contract's fields" do
    login

    assert_response :ok
    assert_equal %w[accessToken coach refreshToken], data.keys.sort
    assert_equal @coach.id, data["coach"]["id"]
    assert_equal "Rania", data["coach"]["fullName"]
    assert_equal @coach.id, CoachApp::AccessToken.verify(data["accessToken"])
    assert_no_match(/\$2a\$|commission/, response.body)
  end

  [ "01012345680", "+201012345680", "٠١٠١٢٣٤٥٦٨٠" ].each do |phone|
    test "login accepts the phone written as #{phone}" do
      login(phone: phone)

      assert_response :ok
    end
  end

  test "a wrong password and an unknown phone get the same refusal" do
    login(password: "wrong-password")
    assert_failure :unauthorized, "invalid credentials"

    login(phone: "01012345681")
    assert_failure :unauthorized, "invalid credentials"
  end

  test "a coach row with an unusable hash gets a refusal, not a 500" do
    @coach.update!(password_hash: "x")
    login

    assert_failure :unauthorized, "invalid credentials"
  end

  test "an invalid phone is refused" do
    login(phone: "123")

    assert_failure :bad_request, "invalid phone"
  end

  test "bad fields are validation failed" do
    [ { password: nil }, { password: "" }, { password: 12345678 }, { phone: nil }, { phone: [ "x" ] }, { country: "XX" } ].each do |fields|
      login(**fields)

      assert_failure :bad_request, "validation failed"
    end
  end

  test "refresh returns a new pair and the old token stops working" do
    login
    first = data["refreshToken"]

    refresh(first)
    assert_response :ok
    assert_equal %w[accessToken refreshToken], data.keys.sort
    assert_equal @coach.id, CoachApp::AccessToken.verify(data["accessToken"])
    assert_not_equal first, data["refreshToken"]

    refresh(first)
    assert_failure :unauthorized, "invalid refresh token"
  end

  test "the new refresh token works" do
    login
    refresh(data["refreshToken"])
    refresh(data["refreshToken"])

    assert_response :ok
  end

  test "refresh refuses an unknown token" do
    refresh("unknown")

    assert_failure :unauthorized, "invalid refresh token"
  end

  test "refresh and logout refuse a missing or non-string token" do
    [ nil, "", 5, [ "x" ] ].each do |token|
      refresh(token)
      assert_failure :bad_request, "validation failed"

      logout(token)
      assert_failure :bad_request, "validation failed"
    end
  end

  test "logout revokes the token" do
    login
    token = data["refreshToken"]

    logout(token)
    assert_response :ok
    assert_equal({ "success" => true, "data" => {} }, response.parsed_body)

    refresh(token)
    assert_failure :unauthorized, "invalid refresh token"
  end

  test "logout with an unknown token is still 200" do
    logout("unknown")

    assert_response :ok
  end
end
