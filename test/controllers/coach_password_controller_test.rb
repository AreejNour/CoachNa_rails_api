require "test_helper"

class CoachPasswordControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(full_name: "Mona Coach", phone: "+201001234567", email: "mona@example.com",
                           password_hash: CoachApp::Password.digest("random-initial"), status: "approved",
                           specialties: [ "weight_loss" ])
    @token = Admin::CoachPasswordSetup.token_for(@coach)
  end

  def set_password(token, password: "newpass123", confirmation: password)
    post "/coach-password/#{token}", params: { password: password, password_confirmation: confirmation }
  end

  test "valid token shows the form without an admin session" do
    get "/coach-password/#{@token}"
    assert_response :ok
    assert_includes @response.body, "Choose your password"
  end

  test "setting a password lets the coach log in with it, then the link is spent" do
    set_password(@token)
    assert_response :ok
    assert_includes @response.body, "Password saved"
    assert CoachApp::Password.verify("newpass123", @coach.reload.password_hash)

    get "/coach-password/#{@token}"
    assert_response :gone
    assert_includes @response.body, "no longer valid"
    hash = @coach.reload.password_hash
    set_password(@token, password: "another123")
    assert_response :gone
    assert_equal hash, @coach.reload.password_hash
  end

  test "token older than 72 hours is expired" do
    travel 73.hours do
      get "/coach-password/#{@token}"
      assert_response :gone
      set_password(@token)
      assert_response :gone
    end
    assert_not CoachApp::Password.verify("newpass123", @coach.reload.password_hash)
  end

  test "tampered token is expired" do
    get "/coach-password/#{@token}x"
    assert_response :gone
    get "/coach-password/garbage"
    assert_response :gone
  end

  test "mismatched or short passwords are rejected and change nothing" do
    hash = @coach.password_hash
    set_password(@token, password: "newpass123", confirmation: "different123")
    assert_response :unprocessable_entity
    assert_includes @response.body, "Passwords do not match."
    set_password(@token, password: "short", confirmation: "short")
    assert_response :unprocessable_entity
    assert_includes @response.body, "at least 8"
    assert_equal hash, @coach.reload.password_hash
  end

  test "post requires a CSRF token when forgery protection is on" do
    CoachPasswordController.allow_forgery_protection = true
    get "/coach-password/#{@token}"
    assert_includes @response.body, "authenticity_token"
    set_password(@token)
    assert_response :unprocessable_entity
    assert_not CoachApp::Password.verify("newpass123", @coach.reload.password_hash)
  ensure
    CoachPasswordController.allow_forgery_protection = false
  end

  test "admin pages still require a session" do
    get "/admin"
    assert_redirected_to "/admin/login"
  end
end
