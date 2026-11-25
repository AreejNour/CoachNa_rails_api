require "test_helper"

class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(email: "team@coachna.app", name: "Team", password: "Secret123")
  end

  test "GET /admin/login renders the form" do
    get "/admin/login"
    assert_response :ok
  end

  test "POST /admin/login with right creds signs in and redirects to /admin" do
    post "/admin/login", params: { email: "team@coachna.app", password: "Secret123" }
    assert_redirected_to "/admin"
    assert_equal @admin.id, session[:admin_id]
  end

  test "POST /admin/login with wrong password re-renders and sets no session" do
    post "/admin/login", params: { email: "team@coachna.app", password: "wrong" }
    assert_response :ok
    assert_nil session[:admin_id]
  end

  test "DELETE /admin/logout clears the session and redirects to login" do
    post "/admin/login", params: { email: "team@coachna.app", password: "Secret123" }
    delete "/admin/logout"
    assert_redirected_to "/admin/login"
    assert_nil session[:admin_id]
  end

  test "GET /admin without a session redirects to login" do
    get "/admin"
    assert_redirected_to "/admin/login"
  end
end
