require "test_helper"

class CoachApp::DevicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(phone: "+201012345690", password_hash: "x", full_name: "Karim")
    @auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  end

  def register(token: "ExponentPushToken[abc]", platform: "ios", language: "ar", headers: @auth)
    post "/coach/devices", as: :json, headers: headers, params: { token: token, platform: platform, language: language }
  end

  test "registers a token for the coach" do
    register

    assert_response :ok
    row = DeviceToken.find_by!(token: "ExponentPushToken[abc]")
    assert_equal [ "coach", @coach.id, "ios", "ar" ], [ row.owner_type, row.owner_id, row.platform, row.language ]
  end

  test "registering again upserts by token" do
    register
    register(platform: "android", language: "en")

    assert_response :ok
    assert_equal 1, DeviceToken.where(token: "ExponentPushToken[abc]").count
    row = DeviceToken.find_by!(token: "ExponentPushToken[abc]")
    assert_equal [ "android", "en" ], [ row.platform, row.language ]
  end

  test "a token held by a client moves to the coach" do
    client = Client.create!(phone: "+201012345691", password_hash: "x", full_name: "Sara")
    DeviceToken.create!(owner_type: "client", owner_id: client.id, token: "ExponentPushToken[abc]", platform: "ios", language: "en")

    register

    assert_response :ok
    rows = DeviceToken.where(token: "ExponentPushToken[abc]")
    assert_equal 1, rows.count
    assert_equal [ "coach", @coach.id ], [ rows.first.owner_type, rows.first.owner_id ]
  end

  test "bad bodies are refused" do
    [ { token: "" }, { token: nil }, { platform: "web" }, { language: "fr" }, { token: 5 } ].each do |fields|
      register(**fields)

      assert_response :bad_request
      assert_equal({ "success" => false, "error" => "validation failed" }, response.parsed_body)
    end
  end

  test "requires a coach" do
    register(headers: {})

    assert_response :unauthorized
  end

  test "deletes the coach's own token" do
    register
    delete "/coach/devices/#{ERB::Util.url_encode('ExponentPushToken[abc]')}", headers: @auth

    assert_response :ok
    assert_equal 0, DeviceToken.count
  end

  test "deleting another owner's or an unknown token is a quiet 200 that changes nothing" do
    DeviceToken.create!(owner_type: "client", owner_id: SecureRandom.uuid, token: "other", platform: "ios", language: "ar")

    delete "/coach/devices/other", headers: @auth
    assert_response :ok
    delete "/coach/devices/nope", headers: @auth
    assert_response :ok

    assert_equal 1, DeviceToken.count
  end
end
