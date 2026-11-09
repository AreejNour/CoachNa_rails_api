require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  class ProbeController < ApplicationController
    def api_error = raise(ApiError.new(409, "phone already registered"))
    def boom = raise("secret database detail")
    def created = render_success({ id: 1 }, status: :created)
    def echo = render_success({ name: params[:name] })
  end

  with_routing do |routes|
    routes.draw do
      post "/probe/api_error", to: "application_controller_test/probe#api_error"
      post "/probe/boom", to: "application_controller_test/probe#boom"
      post "/probe/created", to: "application_controller_test/probe#created"
      post "/probe/echo", to: "application_controller_test/probe#echo"
    end
  end

  test "render_success wraps data in the envelope with the given status" do
    post "/probe/created"

    assert_response :created
    assert_equal({ "success" => true, "data" => { "id" => 1 } }, response.parsed_body)
  end

  test "ApiError becomes its status and message" do
    post "/probe/api_error"

    assert_response :conflict
    assert_equal({ "success" => false, "error" => "phone already registered" }, response.parsed_body)
  end

  test "an unexpected error is a 500 that hides the detail" do
    post "/probe/boom"

    assert_response :internal_server_error
    assert_equal({ "success" => false, "error" => "internal error" }, response.parsed_body)
  end

  test "malformed JSON is 400 validation failed" do
    post "/probe/echo", params: "{not json", headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    assert_equal({ "success" => false, "error" => "validation failed" }, response.parsed_body)
  end
end

class UnknownRouteTest < ActionDispatch::IntegrationTest
  test "an unknown GET route is a 404 in the envelope" do
    get "/nope"

    assert_response :not_found
    assert_equal({ "success" => false, "error" => "not found" }, response.parsed_body)
  end

  test "an unknown POST route with a file extension is a 404 in the envelope" do
    post "/nope/deeper.json"

    assert_response :not_found
    assert_equal({ "success" => false, "error" => "not found" }, response.parsed_body)
  end
end
