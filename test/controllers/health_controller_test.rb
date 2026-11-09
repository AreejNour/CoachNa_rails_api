require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "GET /health returns the contract body" do
    get "/health"

    assert_response :ok
    assert_equal({ "success" => true, "data" => { "status" => "ok", "service" => "coach-rails-api" } }, response.parsed_body)
  end
end
